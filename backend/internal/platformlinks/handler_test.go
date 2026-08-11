package platformlinks

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/require"
)

func TestAppleAppSiteAssociation(t *testing.T) {
	e := echo.New()
	req := httptest.NewRequest("GET", "/.well-known/apple-app-site-association", nil)
	res := httptest.NewRecorder()
	c := e.NewContext(req, res)

	err := NewHandler(Config{AppleTeamID: "TEAM123"}).AppleAppSiteAssociation(c)
	require.NoError(t, err)
	require.Equal(t, http.StatusOK, res.Code)
	var body struct {
		Applinks struct {
			Details []struct {
				AppIDs     []string `json:"appIDs"`
				Components []struct {
					Path string `json:"/"`
				} `json:"components"`
			} `json:"details"`
		} `json:"applinks"`
	}
	require.NoError(t, json.Unmarshal(res.Body.Bytes(), &body))
	require.Equal(t, []string{"TEAM123.com.rigley.supanotes"}, body.Applinks.Details[0].AppIDs)
	require.Equal(t, "/s/*", body.Applinks.Details[0].Components[0].Path)
}

func TestAssetLinks(t *testing.T) {
	e := echo.New()
	req := httptest.NewRequest("GET", "/.well-known/assetlinks.json", nil)
	res := httptest.NewRecorder()
	c := e.NewContext(req, res)

	err := NewHandler(Config{
		AndroidSHA256CertFingerprints: []string{"AA:BB", "CC:DD"},
	}).AssetLinks(c)
	require.NoError(t, err)
	require.Equal(t, http.StatusOK, res.Code)
	var body []struct {
		Target struct {
			PackageName  string   `json:"package_name"`
			Fingerprints []string `json:"sha256_cert_fingerprints"`
		} `json:"target"`
	}
	require.NoError(t, json.Unmarshal(res.Body.Bytes(), &body))
	require.Equal(t, "com.example.supanotes", body[0].Target.PackageName)
	require.Equal(t, []string{"AA:BB", "CC:DD"}, body[0].Target.Fingerprints)
}

func TestAssociationRequiresSigningConfiguration(t *testing.T) {
	e := echo.New()
	for name, handler := range map[string]echo.HandlerFunc{
		"apple":   NewHandler(Config{}).AppleAppSiteAssociation,
		"android": NewHandler(Config{}).AssetLinks,
	} {
		t.Run(name, func(t *testing.T) {
			req := httptest.NewRequest("GET", "/.well-known/", nil)
			res := httptest.NewRecorder()
			err := handler(e.NewContext(req, res))
			require.NoError(t, err)
			require.Equal(t, http.StatusServiceUnavailable, res.Code)
		})
	}
}
