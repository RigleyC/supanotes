package alexa

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/shoppinglist"
	"github.com/RigleyC/supanotes/pkg/auth"
)

// CommandService is the narrow seam used by the Alexa adapter.
type CommandService interface {
	AddItem(ctx context.Context, userID pgtype.UUID, item string, operationID uuid.UUID) error
}

type RequestAuthenticator interface {
	Verify(ctx context.Context, body []byte, headers http.Header) error
}

type Handler struct {
	commands      CommandService
	jwtSecret     string
	applicationID string
	tokenOptions  auth.TokenOptions
	authenticator RequestAuthenticator
	idempotency   idempotencyStore
	now           func() time.Time
}

func NewHandler(commands CommandService, jwtSecret, applicationID string, tokenOptions auth.TokenOptions, authenticator RequestAuthenticator, idempotency idempotencyStore) *Handler {
	return &Handler{
		commands:      commands,
		jwtSecret:     jwtSecret,
		applicationID: applicationID,
		tokenOptions:  tokenOptions,
		authenticator: authenticator,
		idempotency:   idempotency,
		now:           time.Now,
	}
}

type request struct {
	Session struct {
		New bool `json:"new"`
	} `json:"session"`
	Context struct {
		System struct {
			Application struct {
				ApplicationID string `json:"applicationId"`
			} `json:"application"`
			User struct {
				AccessToken string `json:"accessToken"`
			} `json:"user"`
		} `json:"System"`
	} `json:"context"`
	Request struct {
		Type      string `json:"type"`
		RequestID string `json:"requestId"`
		Timestamp string `json:"timestamp"`
		Intent    struct {
			Name  string `json:"name"`
			Slots map[string]struct {
				Value string `json:"value"`
			} `json:"slots"`
		} `json:"intent"`
	} `json:"request"`
}

type response struct {
	Version  string        `json:"version"`
	Response alexaResponse `json:"response"`
}

type alexaResponse struct {
	OutputSpeech     outputSpeech `json:"outputSpeech"`
	ShouldEndSession bool         `json:"shouldEndSession"`
}

type outputSpeech struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

func (h *Handler) Handle(c echo.Context) error {
	body, err := io.ReadAll(io.LimitReader(c.Request().Body, maxAlexaRequestBody+1))
	if err != nil || len(body) > maxAlexaRequestBody {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid Alexa request"})
	}
	if h.authenticator == nil || h.authenticator.Verify(c.Request().Context(), body, c.Request().Header) != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid Alexa request"})
	}

	var req request
	if err := json.Unmarshal(body, &req); err != nil || strings.TrimSpace(req.Request.RequestID) == "" || len(req.Request.RequestID) > 255 {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid Alexa request"})
	}
	req.Request.RequestID = strings.TrimSpace(req.Request.RequestID)
	if err := validateRequestTimestamp(req.Request.Timestamp, h.now()); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid Alexa request"})
	}
	c.Response().Header().Set("X-Request-ID", req.Request.RequestID)
	if h.applicationID == "" || req.Context.System.Application.ApplicationID != h.applicationID {
		return c.NoContent(http.StatusForbidden)
	}
	if req.Request.Type != "IntentRequest" || req.Request.Intent.Name != "AddShoppingItemIntent" {
		return c.JSON(http.StatusOK, speak("Esse comando ainda não está disponível."))
	}

	claims, err := auth.ParseAccessToken(
		strings.TrimSpace(req.Context.System.User.AccessToken),
		h.jwtSecret,
		h.tokenOptions,
	)
	if err != nil {
		return c.JSON(http.StatusOK, speak("Você precisa vincular sua conta do SupaNotes à Alexa."))
	}
	userID, err := uuid.Parse(claims.UserID)
	if err != nil {
		return c.JSON(http.StatusOK, speak("Não consegui identificar sua conta do SupaNotes."))
	}
	item := strings.TrimSpace(req.Request.Intent.Slots["item"].Value)
	operationID := operationIDForRequest(h.applicationID, req.Request.RequestID)
	if h.idempotency == nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "Alexa idempotency is not configured"})
	}
	decision, err := h.idempotency.Acquire(c.Request().Context(), h.applicationID, req.Request.RequestID, bodyFingerprint(body))
	if err != nil {
		if errors.Is(err, errRequestIDPayloadMismatch) {
			return c.JSON(http.StatusBadRequest, map[string]string{"error": "requestId was already used for another request"})
		}
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "Alexa request could not be reserved"})
	}
	if decision.response != nil {
		return c.JSON(http.StatusOK, *decision.response)
	}
	if decision.pending {
		return c.JSON(http.StatusOK, speak("Esse pedido ainda está sendo processado. Tente novamente em instantes."))
	}
	if err := h.commands.AddItem(c.Request().Context(), pgtype.UUID{Bytes: [16]byte(userID), Valid: true}, item, operationID); err != nil {
		switch {
		case errors.Is(err, shoppinglist.ErrEmptyItem):
			result := speak("Qual item devo adicionar?")
			if completeErr := h.idempotency.Complete(c.Request().Context(), decision.reservation, result); completeErr != nil {
				return completeErr
			}
			return c.JSON(http.StatusOK, result)
		case errors.Is(err, shoppinglist.ErrShoppingNotFound):
			result := speak("Não encontrei uma nota chamada Lista de compras no SupaNotes.")
			if completeErr := h.idempotency.Complete(c.Request().Context(), decision.reservation, result); completeErr != nil {
				return completeErr
			}
			return c.JSON(http.StatusOK, result)
		case errors.Is(err, shoppinglist.ErrShoppingAmbiguous):
			result := speak("Encontrei mais de uma nota chamada Lista de compras. Não adicionei o item para evitar ambiguidade.")
			if completeErr := h.idempotency.Complete(c.Request().Context(), decision.reservation, result); completeErr != nil {
				return completeErr
			}
			return c.JSON(http.StatusOK, result)
		default:
			result := speak("Não consegui adicionar o item agora.")
			if completeErr := h.idempotency.Complete(c.Request().Context(), decision.reservation, result); completeErr != nil {
				return completeErr
			}
			return c.JSON(http.StatusOK, result)
		}
	}
	result := speak(item + " foi adicionado à Lista de compras do SupaNotes.")
	if err := h.idempotency.Complete(c.Request().Context(), decision.reservation, result); err != nil {
		return err
	}
	return c.JSON(http.StatusOK, result)
}

const maxAlexaRequestBody = 1024 * 1024

func validateRequestTimestamp(raw string, now time.Time) error {
	timestamp, err := time.Parse(time.RFC3339, strings.TrimSpace(raw))
	if err != nil || timestamp.IsZero() || absDuration(now.Sub(timestamp)) > maxAlexaRequestAge {
		return errors.New("Alexa request timestamp is outside the allowed tolerance")
	}
	return nil
}

func absDuration(value time.Duration) time.Duration {
	if value < 0 {
		return -value
	}
	return value
}

func bodyFingerprint(body []byte) string {
	hash := sha256.Sum256(body)
	return hex.EncodeToString(hash[:])
}

func operationIDForRequest(applicationID, requestID string) uuid.UUID {
	return uuid.NewSHA1(uuid.NameSpaceOID, []byte(applicationID+"\x00"+requestID))
}

func speak(text string) response {
	return response{Version: "1.0", Response: alexaResponse{OutputSpeech: outputSpeech{Type: "PlainText", Text: text}, ShouldEndSession: true}}
}
