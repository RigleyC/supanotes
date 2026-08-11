package platformlinks

import (
	"net/http"

	"github.com/labstack/echo/v4"

	"github.com/RigleyC/supanotes/internal/web"
)

const (
	iosBundleID        = "com.rigley.supanotes"
	androidPackageName = "com.example.supanotes"
)

type Config struct {
	AppleTeamID                   string
	AndroidSHA256CertFingerprints []string
}

type Handler struct {
	appleTeamID                   string
	androidSHA256CertFingerprints []string
}

type appleAssociation struct {
	Applinks appleAppLinks `json:"applinks"`
}

type appleAppLinks struct {
	Details []appleAppDetails `json:"details"`
}

type appleAppDetails struct {
	AppIDs     []string            `json:"appIDs"`
	Components []appleAppComponent `json:"components"`
}

type appleAppComponent struct {
	Path string `json:"/"`
}

type androidAssociation struct {
	Relation []string                 `json:"relation"`
	Target   androidAssociationTarget `json:"target"`
}

type androidAssociationTarget struct {
	Namespace              string   `json:"namespace"`
	PackageName            string   `json:"package_name"`
	SHA256CertFingerprints []string `json:"sha256_cert_fingerprints"`
}

func NewHandler(cfg Config) *Handler {
	return &Handler{
		appleTeamID:                   cfg.AppleTeamID,
		androidSHA256CertFingerprints: append([]string(nil), cfg.AndroidSHA256CertFingerprints...),
	}
}

func (h *Handler) AppleAppSiteAssociation(c echo.Context) error {
	if h.appleTeamID == "" {
		return web.JSONError(c, http.StatusServiceUnavailable, "iOS app association is not configured")
	}

	return c.JSON(http.StatusOK, appleAssociation{
		Applinks: appleAppLinks{
			Details: []appleAppDetails{{
				AppIDs:     []string{h.appleTeamID + "." + iosBundleID},
				Components: []appleAppComponent{{Path: "/s/*"}},
			}},
		},
	})
}

func (h *Handler) AssetLinks(c echo.Context) error {
	if len(h.androidSHA256CertFingerprints) == 0 {
		return web.JSONError(c, http.StatusServiceUnavailable, "Android app association is not configured")
	}

	return c.JSON(http.StatusOK, []androidAssociation{{
		Relation: []string{"delegate_permission/common.handle_all_urls"},
		Target: androidAssociationTarget{
			Namespace:              "android_app",
			PackageName:            androidPackageName,
			SHA256CertFingerprints: h.androidSHA256CertFingerprints,
		},
	}})
}
