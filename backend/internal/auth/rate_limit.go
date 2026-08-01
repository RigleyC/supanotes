package auth

import (
	"sync"
	"time"
)

const (
	defaultAuthRateLimitWindow = time.Minute
	defaultAuthSourceLimit     = 30
	defaultAuthIdentifierLimit = 10
)

type rateLimitBucket struct {
	started time.Time
	count   int
}

type AuthRateLimiter struct {
	mu                sync.Mutex
	now               func() time.Time
	window            time.Duration
	sourceLimit       int
	identifierLimit   int
	sourceBuckets     map[string]rateLimitBucket
	identifierBuckets map[string]rateLimitBucket
}

func NewAuthRateLimiter() *AuthRateLimiter {
	return newAuthRateLimiter(time.Now, defaultAuthRateLimitWindow, defaultAuthSourceLimit, defaultAuthIdentifierLimit)
}

func newAuthRateLimiter(now func() time.Time, window time.Duration, sourceLimit, identifierLimit int) *AuthRateLimiter {
	return &AuthRateLimiter{
		now:               now,
		window:            window,
		sourceLimit:       sourceLimit,
		identifierLimit:   identifierLimit,
		sourceBuckets:     make(map[string]rateLimitBucket),
		identifierBuckets: make(map[string]rateLimitBucket),
	}
}

func (r *AuthRateLimiter) Allow(endpoint, source, identifier string) bool {
	now := r.now()
	r.mu.Lock()
	defer r.mu.Unlock()

	if !allowRate(r.sourceBuckets, endpoint+"|source|"+source, now, r.window, r.sourceLimit) {
		return false
	}
	if identifier == "" {
		return true
	}
	return allowRate(r.identifierBuckets, endpoint+"|identifier|"+identifier, now, r.window, r.identifierLimit)
}

func allowRate(buckets map[string]rateLimitBucket, key string, now time.Time, window time.Duration, limit int) bool {
	for existingKey, bucket := range buckets {
		if now.Sub(bucket.started) >= window {
			delete(buckets, existingKey)
		}
	}
	bucket, ok := buckets[key]
	if !ok || now.Sub(bucket.started) >= window {
		bucket = rateLimitBucket{started: now}
	}
	if bucket.count >= limit {
		return false
	}
	bucket.count++
	buckets[key] = bucket
	return true
}
