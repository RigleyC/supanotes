package linkpreview

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"regexp"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/sync/singleflight"
)

const (
	defaultCacheCapacity    = 256
	defaultCacheTTL         = 15 * time.Minute
	defaultConnectTimeout   = 3 * time.Second
	defaultHeaderTimeout    = 3 * time.Second
	defaultRequestTimeout   = 6 * time.Second
	defaultResponseByteSize = 256 * 1024
	defaultMaxRedirects     = 3
)

var (
	errUnsafeURL         = errors.New("unsafe url")
	errUnexpectedContent = errors.New("unexpected content type")
)

type Preview struct {
	URL         string `json:"url"`
	Title       string `json:"title"`
	Description string `json:"description"`
	ImageURL    string `json:"image_url,omitempty"`
	Domain      string `json:"domain"`
}

type Service interface {
	Fetch(ctx context.Context, rawURL string) (*Preview, error)
	Metrics() Metrics
}

type Metrics struct {
	CacheEntries   int
	CacheCapacity  int
	BlockedFetches int64
}

type service struct {
	client         *http.Client
	cache          *previewCache
	group          singleflight.Group
	maxBodyBytes   int64
	normalizeURL   func(string) (*url.URL, string, error)
	blockedFetches atomic.Int64
}

type serviceOptions struct {
	client       *http.Client
	cacheTTL     time.Duration
	cacheCap     int
	maxBodyBytes int64
	normalizeURL func(string) (*url.URL, string, error)
	now          func() time.Time
}

func NewService() Service {
	return newService(serviceOptions{})
}

func newService(opts serviceOptions) *service {
	cacheTTL := opts.cacheTTL
	if cacheTTL == 0 {
		cacheTTL = defaultCacheTTL
	}
	cacheCap := opts.cacheCap
	if cacheCap == 0 {
		cacheCap = defaultCacheCapacity
	}
	maxBodyBytes := opts.maxBodyBytes
	if maxBodyBytes == 0 {
		maxBodyBytes = defaultResponseByteSize
	}
	normalizeURLFn := opts.normalizeURL
	if normalizeURLFn == nil {
		normalizeURLFn = normalizePreviewURL
	}
	client := opts.client
	if client == nil {
		client = newSafeHTTPClient()
	}
	now := opts.now
	if now == nil {
		now = time.Now
	}

	return &service{
		client:       client,
		cache:        newPreviewCache(cacheCap, cacheTTL, now),
		maxBodyBytes: maxBodyBytes,
		normalizeURL: normalizeURLFn,
	}
}

func newSafeHTTPClient() *http.Client {
	transport := &http.Transport{
		DialContext:           safeDialContext,
		TLSClientConfig:       &tls.Config{MinVersion: tls.VersionTLS12},
		Proxy:                 nil,
		ResponseHeaderTimeout: defaultHeaderTimeout,
		ExpectContinueTimeout: time.Second,
		IdleConnTimeout:       30 * time.Second,
	}

	client := &http.Client{
		Timeout:   defaultRequestTimeout,
		Transport: transport,
	}
	client.CheckRedirect = func(req *http.Request, via []*http.Request) error {
		if len(via) >= defaultMaxRedirects {
			return http.ErrUseLastResponse
		}
		if _, _, err := normalizePreviewURL(req.URL.String()); err != nil {
			return err
		}
		return nil
	}
	return client
}

var (
	ogTitleRe  = regexp.MustCompile(`(?i)<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']`)
	ogDescRe   = regexp.MustCompile(`(?i)<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']`)
	ogImageRe  = regexp.MustCompile(`(?i)<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']`)
	titleTagRe = regexp.MustCompile(`(?i)<title[^>]*>([^<]+)</title>`)

	reservedPrefixes = mustParsePrefixes(
		"0.0.0.0/8",
		"100.64.0.0/10",
		"192.0.0.0/24",
		"192.0.2.0/24",
		"198.18.0.0/15",
		"198.51.100.0/24",
		"203.0.113.0/24",
		"240.0.0.0/4",
		"255.255.255.255/32",
		"::/128",
		"64:ff9b:1::/48",
		"100::/64",
		"2001:db8::/32",
		"2002::/16",
	)
)

func (s *service) Fetch(ctx context.Context, rawURL string) (*Preview, error) {
	parsedURL, cacheKey, err := s.normalizeURL(rawURL)
	if err != nil {
		s.blockedFetches.Add(1)
		return nil, err
	}
	if preview, ok := s.cache.get(cacheKey); ok {
		return preview, nil
	}

	value, err, _ := s.group.Do(cacheKey, func() (any, error) {
		if preview, ok := s.cache.get(cacheKey); ok {
			return preview, nil
		}
		preview, fetchErr := s.fetch(ctx, parsedURL, cacheKey)
		if fetchErr != nil {
			return nil, fetchErr
		}
		s.cache.set(cacheKey, preview)
		return preview, nil
	})
	if err != nil {
		return nil, err
	}
	return value.(*Preview), nil
}

func (s *service) Metrics() Metrics {
	cacheEntries, cacheCapacity := s.cache.stats()
	return Metrics{
		CacheEntries:   cacheEntries,
		CacheCapacity:  cacheCapacity,
		BlockedFetches: s.blockedFetches.Load(),
	}
}

func SafeURLSummary(rawURL string) string {
	parsedURL, err := url.Parse(rawURL)
	if err != nil || parsedURL.Hostname() == "" {
		return "invalid-url"
	}
	if parsedURL.Scheme == "" {
		return parsedURL.Hostname()
	}
	return strings.ToLower(parsedURL.Scheme) + "://" + strings.ToLower(parsedURL.Hostname())
}

func (s *service) fetch(ctx context.Context, parsedURL *url.URL, canonicalURL string) (*Preview, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, parsedURL.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("build preview request: %w", err)
	}
	req.Header.Set("User-Agent", "SupaNotes/1.0 LinkPreview (+https://supanotes.app)")
	req.Header.Set("Accept", "text/html,application/xhtml+xml;q=0.9")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return nil, fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}
	if !isHTMLResponse(resp.Header.Get("Content-Type")) {
		return nil, errUnexpectedContent
	}

	limited := io.LimitReader(resp.Body, s.maxBodyBytes+1)
	body, err := io.ReadAll(limited)
	if err != nil {
		return nil, fmt.Errorf("read body: %w", err)
	}
	if int64(len(body)) > s.maxBodyBytes {
		return nil, fmt.Errorf("response too large")
	}

	html := string(body)
	p := &Preview{URL: canonicalURL, Domain: parsedURL.Hostname()}

	if m := ogTitleRe.FindStringSubmatch(html); len(m) > 1 {
		p.Title = strings.TrimSpace(m[1])
	} else if m := titleTagRe.FindStringSubmatch(html); len(m) > 1 {
		p.Title = strings.TrimSpace(m[1])
	}
	if m := ogDescRe.FindStringSubmatch(html); len(m) > 1 {
		p.Description = strings.TrimSpace(m[1])
	}
	if m := ogImageRe.FindStringSubmatch(html); len(m) > 1 {
		p.ImageURL = strings.TrimSpace(m[1])
	}

	return p, nil
}

func normalizePreviewURL(rawURL string) (*url.URL, string, error) {
	parsedURL, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil {
		return nil, "", fmt.Errorf("%w: parse: %v", errUnsafeURL, err)
	}
	if !parsedURL.IsAbs() || parsedURL.Host == "" {
		return nil, "", fmt.Errorf("%w: url must be absolute", errUnsafeURL)
	}
	if parsedURL.User != nil {
		return nil, "", fmt.Errorf("%w: credentials are not allowed", errUnsafeURL)
	}
	switch parsedURL.Scheme {
	case "http", "https":
	default:
		return nil, "", fmt.Errorf("%w: unsupported scheme", errUnsafeURL)
	}
	if parsedURL.Fragment != "" {
		parsedURL.Fragment = ""
	}
	parsedURL.Scheme = strings.ToLower(parsedURL.Scheme)
	parsedURL.Host = strings.ToLower(parsedURL.Host)
	if err := validateHost(parsedURL.Hostname()); err != nil {
		return nil, "", err
	}
	return parsedURL, parsedURL.String(), nil
}

func validateHost(host string) error {
	if host == "" {
		return fmt.Errorf("%w: missing host", errUnsafeURL)
	}
	if ip, err := netip.ParseAddr(host); err == nil {
		if !isPublicIP(ip) {
			return fmt.Errorf("%w: non-public ip", errUnsafeURL)
		}
	}
	return nil
}

func safeDialContext(ctx context.Context, network, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, fmt.Errorf("split host: %w", err)
	}
	if err := validateHost(host); err != nil {
		return nil, err
	}

	resolveCtx, cancel := context.WithTimeout(ctx, defaultConnectTimeout)
	defer cancel()
	ips, err := net.DefaultResolver.LookupNetIP(resolveCtx, "ip", host)
	if err != nil {
		return nil, fmt.Errorf("resolve host: %w", err)
	}
	if len(ips) == 0 {
		return nil, fmt.Errorf("%w: no resolved addresses", errUnsafeURL)
	}
	for _, ip := range ips {
		if !isPublicIP(ip) {
			return nil, fmt.Errorf("%w: resolved non-public ip", errUnsafeURL)
		}
	}

	sort.Slice(ips, func(i, j int) bool {
		return ips[i].String() < ips[j].String()
	})

	var lastErr error
	for _, ip := range ips {
		dialer := net.Dialer{Timeout: defaultConnectTimeout}
		conn, err := dialer.DialContext(ctx, network, net.JoinHostPort(ip.String(), port))
		if err == nil {
			return conn, nil
		}
		lastErr = err
	}
	return nil, fmt.Errorf("dial validated address: %w", lastErr)
}

func isPublicIP(ip netip.Addr) bool {
	if !ip.IsValid() {
		return false
	}
	if ip.Is4In6() {
		ip = ip.Unmap()
	}
	return !ip.IsLoopback() &&
		!ip.IsPrivate() &&
		!ip.IsLinkLocalUnicast() &&
		!ip.IsLinkLocalMulticast() &&
		!ip.IsMulticast() &&
		!ip.IsUnspecified() &&
		!ip.IsInterfaceLocalMulticast() &&
		!isReservedIP(ip)
}

func isReservedIP(ip netip.Addr) bool {
	for _, prefix := range reservedPrefixes {
		if prefix.Contains(ip) {
			return true
		}
	}
	return false
}

func mustParsePrefixes(rawPrefixes ...string) []netip.Prefix {
	prefixes := make([]netip.Prefix, 0, len(rawPrefixes))
	for _, rawPrefix := range rawPrefixes {
		prefix, err := netip.ParsePrefix(rawPrefix)
		if err != nil {
			panic(err)
		}
		prefixes = append(prefixes, prefix)
	}
	return prefixes
}

func isHTMLResponse(contentType string) bool {
	mediaType := strings.ToLower(strings.TrimSpace(strings.Split(contentType, ";")[0]))
	return mediaType == "text/html" || mediaType == "application/xhtml+xml"
}

type cacheEntry struct {
	preview   *Preview
	expiresAt time.Time
}

type previewCache struct {
	mu       sync.Mutex
	items    map[string]cacheEntry
	order    []string
	capacity int
	ttl      time.Duration
	now      func() time.Time
}

func newPreviewCache(capacity int, ttl time.Duration, now func() time.Time) *previewCache {
	return &previewCache{
		items:    make(map[string]cacheEntry),
		capacity: capacity,
		ttl:      ttl,
		now:      now,
	}
}

func (c *previewCache) get(key string) (*Preview, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()

	entry, ok := c.items[key]
	if !ok {
		return nil, false
	}
	if c.now().After(entry.expiresAt) {
		delete(c.items, key)
		c.removeOrderKey(key)
		return nil, false
	}
	return entry.preview, true
}

func (c *previewCache) set(key string, preview *Preview) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if _, exists := c.items[key]; !exists {
		c.order = append(c.order, key)
	}
	c.items[key] = cacheEntry{
		preview:   preview,
		expiresAt: c.now().Add(c.ttl),
	}

	for len(c.items) > c.capacity && len(c.order) > 0 {
		oldest := c.order[0]
		c.order = c.order[1:]
		delete(c.items, oldest)
	}
}

func (c *previewCache) removeOrderKey(key string) {
	for i, candidate := range c.order {
		if candidate == key {
			c.order = append(c.order[:i], c.order[i+1:]...)
			return
		}
	}
}

func (c *previewCache) stats() (entries int, capacity int) {
	c.mu.Lock()
	defer c.mu.Unlock()

	return len(c.items), c.capacity
}
