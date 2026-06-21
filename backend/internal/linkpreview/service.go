package linkpreview

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"sync"
	"time"
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
}

type service struct {
	client *http.Client
	cache  sync.Map
}

func NewService() Service {
	return &service{
		client: &http.Client{Timeout: 5 * time.Second},
	}
}

var (
	ogTitleRe  = regexp.MustCompile(`(?i)<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']`)
	ogDescRe   = regexp.MustCompile(`(?i)<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']`)
	ogImageRe  = regexp.MustCompile(`(?i)<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']`)
	titleTagRe = regexp.MustCompile(`(?i)<title[^>]*>([^<]+)</title>`)
)

func (s *service) Fetch(ctx context.Context, rawURL string) (*Preview, error) {
	if v, ok := s.cache.Load(rawURL); ok {
		return v.(*Preview), nil
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, fmt.Errorf("invalid url: %w", err)
	}
	req.Header.Set("User-Agent", "SupaNotes/1.0 LinkPreview (+https://supanotes.app)")

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch failed: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 512*1024))
	if err != nil {
		return nil, fmt.Errorf("read body: %w", err)
	}
	html := string(body)

	p := &Preview{URL: rawURL, Domain: extractDomain(rawURL)}

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

	s.cache.Store(rawURL, p)
	return p, nil
}

func extractDomain(rawURL string) string {
	rawURL = strings.TrimPrefix(rawURL, "https://")
	rawURL = strings.TrimPrefix(rawURL, "http://")
	parts := strings.SplitN(rawURL, "/", 2)
	return parts[0]
}
