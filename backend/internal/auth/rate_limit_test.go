package auth

import (
	"testing"
	"time"
)

func TestAuthRateLimiter_EnforcesSourceAndIdentifierWindows(t *testing.T) {
	now := time.Unix(100, 0)
	limiter := newAuthRateLimiter(func() time.Time { return now }, time.Minute, 2, 3)

	if !limiter.Allow("login", "ip-1", "user@example.com") {
		t.Fatal("first request should be allowed")
	}
	if !limiter.Allow("login", "ip-1", "user@example.com") {
		t.Fatal("second request should be allowed")
	}
	if limiter.Allow("login", "ip-1", "user@example.com") {
		t.Fatal("third request should be blocked by both limits")
	}
	if !limiter.Allow("login", "ip-2", "user@example.com") {
		t.Fatal("different source should still be allowed before identifier limit")
	}

	now = now.Add(time.Minute)
	if !limiter.Allow("login", "ip-1", "user@example.com") {
		t.Fatal("request should be allowed after the window")
	}
}

func TestAuthRateLimiter_SeparatesEndpoints(t *testing.T) {
	now := time.Unix(100, 0)
	limiter := newAuthRateLimiter(func() time.Time { return now }, time.Minute, 1, 1)

	if !limiter.Allow("login", "ip-1", "user@example.com") {
		t.Fatal("login should be allowed")
	}
	if !limiter.Allow("refresh", "ip-1", "token-digest") {
		t.Fatal("refresh should have its own bucket")
	}
}

func TestAuthRateLimiter_PrunesExpiredBuckets(t *testing.T) {
	now := time.Date(2026, 8, 1, 12, 0, 0, 0, time.UTC)
	limiter := newAuthRateLimiter(func() time.Time { return now }, time.Minute, 10, 10)

	if !limiter.Allow("login", "source-a", "user-a") {
		t.Fatal("first request should be allowed")
	}
	if len(limiter.sourceBuckets) != 1 || len(limiter.identifierBuckets) != 1 {
		t.Fatal("expected one bucket per dimension")
	}

	now = now.Add(time.Minute)
	if !limiter.Allow("login", "source-b", "user-b") {
		t.Fatal("request after the window should be allowed")
	}
	if len(limiter.sourceBuckets) != 1 || len(limiter.identifierBuckets) != 1 {
		t.Fatalf("expired buckets were retained: source=%d identifier=%d", len(limiter.sourceBuckets), len(limiter.identifierBuckets))
	}
}
