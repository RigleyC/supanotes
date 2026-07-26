package linkpreview

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestNormalizePreviewURLRejectsUnsafeURLs(t *testing.T) {
	t.Parallel()

	cases := []string{
		"/relative/path",
		"ftp://example.com/file",
		"http://user:pass@example.com",
		"http://127.0.0.1/",
		"http://10.0.0.5/",
		"http://172.16.0.2/",
		"http://192.168.1.2/",
		"http://169.254.1.1/",
		"http://0.0.0.0/",
		"http://224.0.0.1/",
		"http://[::1]/",
		"http://[fc00::1]/",
	}

	for _, rawURL := range cases {
		rawURL := rawURL
		t.Run(rawURL, func(t *testing.T) {
			t.Parallel()

			_, _, err := normalizePreviewURL(rawURL)
			require.Error(t, err)
		})
	}
}

func TestNormalizePreviewURLNormalizesCacheKey(t *testing.T) {
	t.Parallel()

	parsedURL, cacheKey, err := normalizePreviewURL(" HTTPS://Example.COM/a?b=1#ignored ")
	require.NoError(t, err)
	require.Equal(t, "https", parsedURL.Scheme)
	require.Equal(t, "example.com", parsedURL.Host)
	require.Equal(t, "https://example.com/a?b=1", cacheKey)
}

func TestSafeDialContextRejectsPrivateResolvedAddress(t *testing.T) {
	t.Parallel()

	_, err := safeDialContext(context.Background(), "tcp", "localhost:80")
	require.Error(t, err)
	require.Contains(t, err.Error(), "non-public")
}

func TestRedirectPolicyRejectsUnsafeTargetAndLimitsChain(t *testing.T) {
	t.Parallel()

	client := newSafeHTTPClient()
	require.NotNil(t, client.CheckRedirect)

	privateTarget, err := http.NewRequest(http.MethodGet, "http://127.0.0.1/private", nil)
	require.NoError(t, err)
	err = client.CheckRedirect(privateTarget, []*http.Request{{}, {}})
	require.Error(t, err)

	publicTarget, err := http.NewRequest(http.MethodGet, "https://example.com/final", nil)
	require.NoError(t, err)
	err = client.CheckRedirect(publicTarget, []*http.Request{{}, {}, {}})
	require.ErrorIs(t, err, http.ErrUseLastResponse)
}

func TestFetchParsesHTMLAndCachesByNormalizedURL(t *testing.T) {
	t.Parallel()

	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(`<html><head><title>Fallback</title><meta property="og:title" content="Title"><meta property="og:description" content="Desc"><meta property="og:image" content="https://cdn.example.com/i.png"></head></html>`))
	}))
	defer server.Close()

	svc := newService(serviceOptions{
		client:   server.Client(),
		cacheTTL: time.Minute,
		normalizeURL: func(rawURL string) (*url.URL, string, error) {
			parsed, err := url.Parse(rawURL)
			if err != nil {
				return nil, "", err
			}
			return parsed, "http://example.com/page", nil
		},
	})

	preview, err := svc.Fetch(context.Background(), server.URL+"/page#fragment")
	require.NoError(t, err)
	require.Equal(t, "Title", preview.Title)
	require.Equal(t, "Desc", preview.Description)
	require.Equal(t, "https://cdn.example.com/i.png", preview.ImageURL)
	require.Equal(t, "http://example.com/page", preview.URL)

	preview, err = svc.Fetch(context.Background(), server.URL+"/page")
	require.NoError(t, err)
	require.Equal(t, "Title", preview.Title)
	require.Equal(t, int32(1), requests.Load())
	require.Equal(t, Metrics{CacheEntries: 1, CacheCapacity: defaultCacheCapacity}, svc.Metrics())
}

func TestCacheExpiresAndEvictsOldestEntry(t *testing.T) {
	t.Parallel()

	cache := newPreviewCache(1, time.Millisecond)
	cache.set("first", &Preview{Title: "first"})
	cache.set("second", &Preview{Title: "second"})

	_, ok := cache.get("first")
	require.False(t, ok)

	second, ok := cache.get("second")
	require.True(t, ok)
	require.Equal(t, "second", second.Title)

	time.Sleep(2 * time.Millisecond)
	_, ok = cache.get("second")
	require.False(t, ok)
}

func TestMetricsExposeBlockedFetchesAndCacheOccupancy(t *testing.T) {
	t.Parallel()

	svc := newService(serviceOptions{})

	_, err := svc.Fetch(context.Background(), "http://127.0.0.1/private?token=secret")
	require.Error(t, err)

	metrics := svc.Metrics()
	require.Equal(t, int64(1), metrics.BlockedFetches)
	require.Equal(t, 0, metrics.CacheEntries)
	require.Equal(t, defaultCacheCapacity, metrics.CacheCapacity)
	require.Equal(t, "http://127.0.0.1", SafeURLSummary("http://127.0.0.1/private?token=secret"))
}

func TestFetchRejectsNonHTMLAndOversizedResponses(t *testing.T) {
	t.Parallel()

	testCases := []struct {
		name         string
		contentType  string
		body         string
		maxBodyBytes int64
	}{
		{name: "json", contentType: "application/json", body: `{"title":"no"}`, maxBodyBytes: 1024},
		{name: "too-large", contentType: "text/html", body: strings.Repeat("a", 12), maxBodyBytes: 8},
	}

	for _, tc := range testCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", tc.contentType)
				_, _ = w.Write([]byte(tc.body))
			}))
			defer server.Close()

			svc := newTestService(server, tc.maxBodyBytes)
			_, err := svc.Fetch(context.Background(), server.URL)
			require.Error(t, err)
		})
	}
}

func TestFetchDeduplicatesConcurrentRequests(t *testing.T) {
	t.Parallel()

	var requests atomic.Int32
	started := make(chan struct{})
	release := make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if requests.Add(1) == 1 {
			close(started)
			<-release
		}
		w.Header().Set("Content-Type", "text/html")
		_, _ = w.Write([]byte(`<title>shared</title>`))
	}))
	defer server.Close()

	svc := newTestService(server, 1024)

	const callers = 8
	var wg sync.WaitGroup
	errs := make(chan error, callers)
	for i := 0; i < callers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			preview, err := svc.Fetch(context.Background(), server.URL)
			if err != nil {
				errs <- err
				return
			}
			if preview.Title != "shared" {
				errs <- fmt.Errorf("unexpected title: %s", preview.Title)
			}
		}()
	}

	<-started
	close(release)
	wg.Wait()
	close(errs)

	require.Empty(t, errs)
	require.Equal(t, int32(1), requests.Load())
}

func newTestService(server *httptest.Server, maxBodyBytes int64) *service {
	return newService(serviceOptions{
		client:       server.Client(),
		cacheTTL:     time.Minute,
		maxBodyBytes: maxBodyBytes,
		normalizeURL: func(rawURL string) (*url.URL, string, error) {
			parsed, err := url.Parse(rawURL)
			if err != nil {
				return nil, "", err
			}
			return parsed, rawURL, nil
		},
	})
}
