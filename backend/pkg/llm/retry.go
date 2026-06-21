package llm

import (
	"context"
	"fmt"
	"math/rand"
	"strings"
	"time"
)

type retryClient struct {
	base       Client
	maxRetries int
}

func WithRetry(base Client, maxRetries int) Client {
	return &retryClient{
		base:       base,
		maxRetries: maxRetries,
	}
}

func (r *retryClient) Complete(ctx context.Context, req Request) (*Response, error) {
	var lastErr error

	for attempt := 0; attempt <= r.maxRetries; attempt++ {
		res, err := r.base.Complete(ctx, req)
		if err == nil {
			return res, nil
		}

		lastErr = err

		if !isRetryable(err) || attempt == r.maxRetries {
			break
		}

		backoff := time.Duration(1<<attempt) * time.Second
		jitter := time.Duration(rand.Intn(1000)) * time.Millisecond
		sleepTime := backoff + jitter

		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(sleepTime):
			// continue retry loop
		}
	}

	return nil, fmt.Errorf("llm retry failed after %d attempts: %w", r.maxRetries, lastErr)
}

func (r *retryClient) CompleteStream(ctx context.Context, req Request, onToken func(string) error) (*Response, error) {
	// Retrying streaming requests is complex once tokens start emitting,
	// so we delegate directly to the base client.
	return r.base.CompleteStream(ctx, req, onToken)
}

func isRetryable(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	// Retry on Rate Limit (429) or Server Errors (5xx)
	if strings.Contains(msg, "429") || strings.Contains(msg, "500") || strings.Contains(msg, "502") || strings.Contains(msg, "503") || strings.Contains(msg, "504") {
		return true
	}
	return false
}
