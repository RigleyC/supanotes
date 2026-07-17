package sync

import (
	"encoding/base64"
	"io"
	"net/http"

	"github.com/labstack/echo/v4"
	"github.com/reearth/ygo/crdt"

	"github.com/RigleyC/supanotes/internal/web"
)

// PostSyncHandler handles POST /api/v1/sync/note/:id
//
// The client sends its Yjs update as the binary request body and its
// state vector as the base64-encoded X-State-Vector header. The server
// applies the client's update, computes the diff from the client's state
// vector, and returns the missing updates as the binary response body.
func PostSyncHandler(ydocSvc *YDocService) echo.HandlerFunc {
	return func(c echo.Context) error {
		noteID := c.Param("id")

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
