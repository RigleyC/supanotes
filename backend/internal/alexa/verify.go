package alexa

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strings"
	"time"
)

const (
	maxAlexaRequestAge = 150 * time.Second
	maxCertificateSize = 1024 * 1024
)

var (
	errMissingAlexaSignature      = errors.New("missing Alexa request signature")
	errInvalidAlexaCertificateURL = errors.New("invalid Alexa certificate URL")
)

// CertificateFetcher is injectable so signature verification can be tested
// without contacting Amazon.
type CertificateFetcher func(context.Context, *url.URL) ([]byte, error)

// RequestVerifier validates the signed HTTP envelope sent by Alexa.
type RequestVerifier struct {
	fetch CertificateFetcher
	roots *x509.CertPool
}

func NewRequestVerifier(client *http.Client) *RequestVerifier {
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	certificateClient := &http.Client{
		Transport: client.Transport,
		Timeout:   client.Timeout,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	return &RequestVerifier{
		fetch: func(ctx context.Context, certURL *url.URL) ([]byte, error) {
			req, err := http.NewRequestWithContext(ctx, http.MethodGet, certURL.String(), nil)
			if err != nil {
				return nil, err
			}
			res, err := certificateClient.Do(req)
			if err != nil {
				return nil, err
			}
			defer res.Body.Close()
			if res.StatusCode != http.StatusOK {
				return nil, fmt.Errorf("certificate endpoint returned %s", res.Status)
			}
			body, err := io.ReadAll(io.LimitReader(res.Body, maxCertificateSize+1))
			if err != nil {
				return nil, err
			}
			if len(body) > maxCertificateSize {
				return nil, errors.New("Alexa certificate is too large")
			}
			return body, nil
		},
	}
}

func (v *RequestVerifier) Verify(ctx context.Context, body []byte, headers http.Header) error {
	if v == nil || v.fetch == nil {
		return errors.New("Alexa request verification is not configured")
	}
	certURL, err := validateCertificateURL(headers.Get("SignatureCertChainUrl"))
	if err != nil {
		return err
	}

	signatureHeader := headers.Get("Signature-256")
	hashFunc := crypto.SHA256
	if signatureHeader == "" {
		// Alexa's older contract used Signature/SHA-1. Keep it only as a
		// compatibility path; Signature-256 is always preferred.
		signatureHeader = headers.Get("Signature")
		hashFunc = crypto.SHA1
	}
	if strings.TrimSpace(signatureHeader) == "" {
		return errMissingAlexaSignature
	}
	signature, err := base64.StdEncoding.DecodeString(strings.TrimSpace(signatureHeader))
	if err != nil {
		return errors.New("invalid Alexa request signature encoding")
	}

	pemBytes, err := v.fetch(ctx, certURL)
	if err != nil {
		return fmt.Errorf("download Alexa certificate: %w", err)
	}
	leaf, err := validateCertificateChain(pemBytes, v.roots)
	if err != nil {
		return err
	}
	publicKey, ok := leaf.PublicKey.(*rsa.PublicKey)
	if !ok {
		return errors.New("Alexa signing certificate does not contain an RSA key")
	}

	var digest []byte
	switch hashFunc {
	case crypto.SHA256:
		sum := sha256.Sum256(body)
		digest = sum[:]
	case crypto.SHA1:
		sum := sha1.Sum(body)
		digest = sum[:]
	default:
		return errors.New("unsupported Alexa signature algorithm")
	}
	if err := rsa.VerifyPKCS1v15(publicKey, hashFunc, digest, signature); err != nil {
		return errors.New("invalid Alexa request signature")
	}
	return nil
}

func validateCertificateURL(raw string) (*url.URL, error) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed.Scheme == "" || parsed.Host == "" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" {
		return nil, errInvalidAlexaCertificateURL
	}
	if !strings.EqualFold(parsed.Scheme, "https") || !strings.EqualFold(parsed.Hostname(), "s3.amazonaws.com") {
		return nil, errInvalidAlexaCertificateURL
	}
	if port := parsed.Port(); port != "" && port != "443" {
		return nil, errInvalidAlexaCertificateURL
	}
	parsed.Path = path.Clean(strings.ReplaceAll(parsed.EscapedPath(), "//", "/"))
	if !strings.HasPrefix(parsed.Path, "/echo.api/") {
		return nil, errInvalidAlexaCertificateURL
	}
	parsed.RawPath = ""
	return parsed, nil
}

func validateCertificateChain(pemBytes []byte, roots *x509.CertPool) (*x509.Certificate, error) {
	var certificates []*x509.Certificate
	for len(pemBytes) > 0 {
		block, rest := pem.Decode(pemBytes)
		if block == nil {
			break
		}
		pemBytes = rest
		if block.Type != "CERTIFICATE" {
			continue
		}
		certificate, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			return nil, errors.New("invalid Alexa certificate")
		}
		certificates = append(certificates, certificate)
	}
	if len(certificates) == 0 {
		return nil, errors.New("Alexa certificate chain is empty")
	}
	leaf := certificates[0]
	if len(leaf.DNSNames) == 0 || !containsString(leaf.DNSNames, "echo-api.amazon.com") {
		return nil, errors.New("Alexa signing certificate has no approved SAN")
	}
	if roots == nil {
		var err error
		roots, err = x509.SystemCertPool()
		if err != nil {
			return nil, errors.New("load system certificate roots")
		}
	}
	intermediates := x509.NewCertPool()
	for _, certificate := range certificates[1:] {
		intermediates.AddCert(certificate)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{
		Roots:         roots,
		Intermediates: intermediates,
		DNSName:       "echo-api.amazon.com",
		KeyUsages:     []x509.ExtKeyUsage{x509.ExtKeyUsageAny},
	}); err != nil {
		return nil, errors.New("Alexa certificate chain is not trusted")
	}
	return leaf, nil
}

func containsString(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
