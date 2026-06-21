package llm

import (
	"context"
	"errors"
	"testing"
	"time"
)

type mockFailingClient struct {
	attempts int
}

func (m *mockFailingClient) Complete(ctx context.Context, req Request) (*Response, error) {
	m.attempts++
	// Simulate rate limit for the first two attempts
	if m.attempts <= 2 {
		return nil, errors.New("anthropic API error 429: Too Many Requests")
	}
	// Succeed on third attempt
	return &Response{Content: "success!"}, nil
}

func (m *mockFailingClient) CompleteStream(ctx context.Context, req Request, onToken func(string) error) (*Response, error) {
	res, err := m.Complete(ctx, req)
	if err != nil {
		return nil, err
	}
	if res.Content != "" {
		if err := onToken(res.Content); err != nil {
			return nil, err
		}
	}
	return res, nil
}

type mockNonRetryableClient struct {
	attempts int
}

func (m *mockNonRetryableClient) Complete(ctx context.Context, req Request) (*Response, error) {
	m.attempts++
	return nil, errors.New("anthropic API error 400: Bad Request")
}

func (m *mockNonRetryableClient) CompleteStream(ctx context.Context, req Request, onToken func(string) error) (*Response, error) {
	return m.Complete(ctx, req)
}

func TestWithRetry_SuccessAfterFails(t *testing.T) {
	base := &mockFailingClient{}
	client := WithRetry(base, 3)

	start := time.Now()
	res, err := client.Complete(context.Background(), Request{
		Messages: []Message{{Role: RoleUser, Content: "test"}},
	})
	elapsed := time.Since(start)

	if err != nil {
		t.Fatalf("expected success, got error: %v", err)
	}
	if res.Content != "success!" {
		t.Fatalf("unexpected content: %s", res.Content)
	}
	if base.attempts != 3 {
		t.Fatalf("expected 3 attempts, got %d", base.attempts)
	}

	// first backoff is ~1s, second is ~2s. Total should be roughly > 3s
	if elapsed < 3*time.Second {
		t.Fatalf("expected backoff to take at least 3s, took %v", elapsed)
	}
}

func TestWithRetry_NonRetryable(t *testing.T) {
	base := &mockNonRetryableClient{}
	client := WithRetry(base, 3)

	_, err := client.Complete(context.Background(), Request{
		Messages: []Message{{Role: RoleUser, Content: "test"}},
	})

	if err == nil {
		t.Fatal("expected error, got nil")
	}

	if base.attempts != 1 {
		t.Fatalf("expected 1 attempt (no retries), got %d", base.attempts)
	}
}
