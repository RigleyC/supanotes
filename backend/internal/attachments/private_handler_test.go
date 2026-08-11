package attachments

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/web"
	"github.com/RigleyC/supanotes/pkg/uid"
)

func TestPrivateDownloadStreamsAuthenticatedAttachment(t *testing.T) {
	attachmentID := testUUID(3)
	repo := &deliveryRepo{
		permission: "view",
		attachment: deliveryAttachment(),
	}
	h := NewPrivateHandler(repo, &deliveryStorage{})
	e := echo.New()
	pathID := uid.UUIDToString(attachmentID)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/attachments/"+pathID+"/content", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/api/v1/attachments/:id/content")
	c.SetParamNames("id")
	c.SetParamValues(pathID)
	web.SetUserID(c, uid.UUIDToString(testUUID(2)))

	require.NoError(t, h.Download(c))
	require.Equal(t, http.StatusOK, rec.Code)
	require.Equal(t, "private, no-store", rec.Header().Get("Cache-Control"))
	require.Equal(t, "private content", rec.Body.String())
}

func TestPrivateDownloadReturnsJSONForForbiddenAttachment(t *testing.T) {
	h := NewPrivateHandler(
		&deliveryRepo{permission: "none", attachment: deliveryAttachment()},
		&deliveryStorage{},
	)
	e := echo.New()
	pathID := uid.UUIDToString(testUUID(3))
	req := httptest.NewRequest(http.MethodGet, "/api/v1/attachments/"+pathID+"/content", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetPath("/api/v1/attachments/:id/content")
	c.SetParamNames("id")
	c.SetParamValues(pathID)
	web.SetUserID(c, uid.UUIDToString(testUUID(2)))

	require.NoError(t, h.Download(c))
	require.Equal(t, http.StatusForbidden, rec.Code)
	require.True(t, strings.Contains(rec.Body.String(), `"error"`))
}
