package sync

import (
	"context"
	"encoding/base64"
	"io"
	"net/http"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/labstack/echo/v4"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/internal/web"
)

// NoteAuthorizer checks whether the given user can edit the given note.
type NoteAuthorizer interface {
	CanEditNote(ctx context.Context, noteID, userID pgtype.UUID) (bool, error)
}

type repoAuthorizer struct {
	repo Repository
}

// NewNoteAuthorizer wraps a Repository as a NoteAuthorizer.
func NewNoteAuthorizer(repo Repository) NoteAuthorizer {
	return &repoAuthorizer{repo: repo}
}

func (a *repoAuthorizer) CanEditNote(ctx context.Context, noteID, userID pgtype.UUID) (bool, error) {
	meta, err := a.repo.GetNoteMeta(ctx, noteID)
	if err != nil {
		return false, err
	}
	if meta.DeletedAt.Valid {
		return false, nil
	}
	if meta.UserID == userID {
		return true, nil
	}
	share, shareErr := a.repo.GetNoteShareForUser(ctx, sqlcgen.GetNoteShareForUserParams{
		NoteID: noteID, UserID: userID,
	})
	return shareErr == nil && share.Permission == "edit", nil
}

// PostSyncHandler handles POST /api/v1/sync/note/:id
//
// The client sends its Yjs update as the binary request body and its
// state vector as the base64-encoded X-State-Vector header. The server
// applies the client's update, computes the diff from the client's state
// vector, and returns the missing updates as the binary response body.
func PostSyncHandler(ydocSvc *YDocService, authorizer NoteAuthorizer) echo.HandlerFunc {
	return func(c echo.Context) error {
		userID, err := web.UserID(c)
		if err != nil {
			return web.JSONError(c, http.StatusUnauthorized, "unauthorized")
		}

		noteID := c.Param("id")
		noteUUID, err := parseUUIDStr(noteID)
		if err != nil {
			return web.JSONError(c, http.StatusBadRequest, "invalid note id")
		}

		allowed, err := authorizer.CanEditNote(c.Request().Context(), noteUUID, userID)
		if err != nil {
			return web.JSONError(c, http.StatusInternalServerError, "authorization failed")
		}
		if !allowed {
			return web.JSONError(c, http.StatusForbidden, "note is not editable")
		}

		body, err := io.ReadAll(c.Request().Body)
		if err != nil {
			return web.JSONError(c, http.StatusBadRequest, "failed to read request body")
		}

		var clientStateVectorRaw []byte
		if svHeader := c.Request().Header.Get("X-State-Vector"); svHeader != "" {
			clientStateVectorRaw, err = base64.StdEncoding.DecodeString(svHeader)
			if err != nil {
				return web.JSONError(c, http.StatusBadRequest, "invalid X-State-Vector: not valid base64")
			}
		}

		var responseUpdate []byte
		err = ydocSvc.WithDoc(c.Request().Context(), noteID, func(doc *crdt.Doc) error {
			// Apply client's update if present
			if len(body) > 0 {
				if err := ydocSvc.ApplyNodeMutationLocked(c.Request().Context(), doc, noteID, body); err != nil {
					return err
				}
			}

			// Compute missing updates for the client
			if len(clientStateVectorRaw) > 0 {
				sv, decodeErr := crdt.DecodeStateVectorV1(clientStateVectorRaw)
				if decodeErr != nil {
					return decodeErr
				}
				responseUpdate = crdt.EncodeStateAsUpdateV1(doc, sv)
			} else {
				responseUpdate = crdt.EncodeStateAsUpdateV1(doc, nil)
			}
			return nil
		})
		if err != nil {
			c.Logger().Errorf("PostSyncHandler: %v", err)
			return web.JSONError(c, http.StatusInternalServerError, "sync failed")
		}

		return c.Blob(http.StatusOK, "application/octet-stream", responseUpdate)
	}
}
