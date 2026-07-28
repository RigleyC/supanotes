package alexa

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/shoppinglist"
	"github.com/RigleyC/supanotes/pkg/auth"
)

// CommandService is the narrow seam used by the Alexa adapter.
type CommandService interface {
	AddItem(ctx context.Context, userID pgtype.UUID, item string) error
}

type Handler struct {
	commands      CommandService
	jwtSecret     string
	applicationID string
}

func NewHandler(commands CommandService, jwtSecret, applicationID string) *Handler {
	return &Handler{commands: commands, jwtSecret: jwtSecret, applicationID: applicationID}
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
		Type   string `json:"type"`
		Intent struct {
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
	var req request
	if err := c.Bind(&req); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid Alexa request"})
	}
	if h.applicationID != "" && req.Context.System.Application.ApplicationID != h.applicationID {
		return c.NoContent(http.StatusForbidden)
	}
	if req.Request.Type != "IntentRequest" || req.Request.Intent.Name != "AddShoppingItemIntent" {
		return c.JSON(http.StatusOK, speak("Esse comando ainda não está disponível."))
	}

	claims, err := auth.ParseAccessToken(strings.TrimSpace(req.Context.System.User.AccessToken), h.jwtSecret)
	if err != nil {
		return c.JSON(http.StatusOK, speak("Você precisa vincular sua conta do SupaNotes à Alexa."))
	}
	userID, err := uuid.Parse(claims.UserID)
	if err != nil {
		return c.JSON(http.StatusOK, speak("Não consegui identificar sua conta do SupaNotes."))
	}
	item := strings.TrimSpace(req.Request.Intent.Slots["item"].Value)
	if err := h.commands.AddItem(c.Request().Context(), pgtype.UUID{Bytes: [16]byte(userID), Valid: true}, item); err != nil {
		switch {
		case errors.Is(err, shoppinglist.ErrEmptyItem):
			return c.JSON(http.StatusOK, speak("Qual item devo adicionar?"))
		case errors.Is(err, shoppinglist.ErrShoppingNotFound):
			return c.JSON(http.StatusOK, speak("Não encontrei uma nota chamada Lista de compras no SupaNotes."))
		case errors.Is(err, shoppinglist.ErrShoppingAmbiguous):
			return c.JSON(http.StatusOK, speak("Encontrei mais de uma nota chamada Lista de compras. Não adicionei o item para evitar ambiguidade."))
		default:
			return c.JSON(http.StatusOK, speak("Não consegui adicionar o item agora."))
		}
	}
	return c.JSON(http.StatusOK, speak(item+" foi adicionado à Lista de compras do SupaNotes."))
}

func speak(text string) response {
	return response{Version: "1.0", Response: alexaResponse{OutputSpeech: outputSpeech{Type: "PlainText", Text: text}, ShouldEndSession: true}}
}
