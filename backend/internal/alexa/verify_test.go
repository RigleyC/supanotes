package alexa

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/pem"
	"math/big"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestRequestVerifierValidatesSignatureAndCertificateChain(t *testing.T) {
	chainPEM, signingKey, roots := testCertificateChain(t)
	body := []byte(`{"request":{"requestId":"request-123","timestamp":"2026-09-16T12:00:00Z"}}`)
	digest := sha256Digest(body)
	signature, err := rsa.SignPKCS1v15(rand.Reader, signingKey, crypto.SHA256, digest)
	require.NoError(t, err)

	verifier := &RequestVerifier{
		roots: roots,
		fetch: func(_ context.Context, certURL *url.URL) ([]byte, error) {
			require.Equal(t, "https://s3.amazonaws.com/echo.api/cert.pem", certURL.String())
			return chainPEM, nil
		},
	}
	headers := http.Header{
		"Signaturecertchainurl": []string{"https://s3.amazonaws.com/echo.api/../echo.api/cert.pem"},
		"Signature-256":         []string{base64.StdEncoding.EncodeToString(signature)},
	}

	require.NoError(t, verifier.Verify(context.Background(), body, headers))
}

func TestRequestVerifierRejectsInvalidCertificateURLAndSignature(t *testing.T) {
	chainPEM, signingKey, roots := testCertificateChain(t)
	body := []byte(`{"request":{"requestId":"request-123"}}`)
	verifier := &RequestVerifier{
		roots: roots,
		fetch: func(context.Context, *url.URL) ([]byte, error) { return chainPEM, nil },
	}

	err := verifier.Verify(context.Background(), body, http.Header{
		"Signaturecertchainurl": []string{"https://attacker.example/echo.api/cert.pem"},
		"Signature-256":         []string{"not-base64"},
	})
	require.ErrorIs(t, err, errInvalidAlexaCertificateURL)

	digest := sha256Digest(body)
	signature, err := rsa.SignPKCS1v15(rand.Reader, signingKey, crypto.SHA256, digest)
	require.NoError(t, err)
	signature[0] ^= 1
	err = verifier.Verify(context.Background(), body, http.Header{
		"Signaturecertchainurl": []string{"https://s3.amazonaws.com/echo.api/cert.pem"},
		"Signature-256":         []string{base64.StdEncoding.EncodeToString(signature)},
	})
	require.EqualError(t, err, "invalid Alexa request signature")
}

func TestValidateCertificateURLRejectsQueryAndUntrustedHost(t *testing.T) {
	for _, raw := range []string{
		"http://s3.amazonaws.com/echo.api/cert.pem",
		"https://not-s3.amazonaws.com/echo.api/cert.pem",
		"https://s3.amazonaws.com:8443/echo.api/cert.pem",
		"https://s3.amazonaws.com/echo.api/cert.pem?redirect=https://attacker.example",
		"https://s3.amazonaws.com/not-echo/cert.pem",
	} {
		if _, err := validateCertificateURL(raw); err == nil {
			t.Errorf("validateCertificateURL(%q): want error", raw)
		}
	}
}

func sha256Digest(body []byte) []byte {
	sum := sha256.Sum256(body)
	return sum[:]
}

func testCertificateChain(t *testing.T) ([]byte, *rsa.PrivateKey, *x509.CertPool) {
	t.Helper()
	now := time.Now().UTC()
	rootKey, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	rootTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "Test Alexa Root"},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.Add(time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageDigitalSignature,
	}
	rootDER, err := x509.CreateCertificate(rand.Reader, rootTemplate, rootTemplate, &rootKey.PublicKey, rootKey)
	require.NoError(t, err)
	rootCert, err := x509.ParseCertificate(rootDER)
	require.NoError(t, err)

	leafKey, err := rsa.GenerateKey(rand.Reader, 2048)
	require.NoError(t, err)
	leafTemplate := &x509.Certificate{
		SerialNumber:          big.NewInt(2),
		Subject:               pkix.Name{CommonName: "echo-api.amazon.com"},
		DNSNames:              []string{"echo-api.amazon.com"},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.Add(time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, rootCert, &leafKey.PublicKey, rootKey)
	require.NoError(t, err)

	roots := x509.NewCertPool()
	roots.AddCert(rootCert)
	chain := append(
		pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: leafDER}),
		pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: rootDER})...,
	)
	return chain, leafKey, roots
}

func TestRequestVerifierAcceptsLegacySignatureHeader(t *testing.T) {
	chainPEM, signingKey, roots := testCertificateChain(t)
	body := []byte(strings.TrimSpace(`{"request":{"requestId":"request-123"}}`))
	digest := sha1Digest(body)
	signature, err := rsa.SignPKCS1v15(rand.Reader, signingKey, crypto.SHA1, digest)
	require.NoError(t, err)
	verifier := &RequestVerifier{
		roots: roots,
		fetch: func(context.Context, *url.URL) ([]byte, error) { return chainPEM, nil },
	}
	require.NoError(t, verifier.Verify(context.Background(), body, http.Header{
		"Signaturecertchainurl": []string{"https://s3.amazonaws.com/echo.api/cert.pem"},
		"Signature":             []string{base64.StdEncoding.EncodeToString(signature)},
	}))
}

func sha1Digest(body []byte) []byte {
	sum := sha1.Sum(body)
	return sum[:]
}
