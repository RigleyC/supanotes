package llm

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestGenerateEmbedding_Success(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		resp := embeddingResponse{
			Data: []struct {
				Embedding []float64 `json:"embedding"`
				Index     int       `json:"index"`
			}{
				{Embedding: make([]float64, 1536), Index: 0},
			},
		}
		for i := range resp.Data[0].Embedding {
			resp.Data[0].Embedding[i] = 0.5
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	client := NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	emb, err := client.GenerateEmbedding(context.Background(), "hello")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(emb) != 1536 {
		t.Fatalf("expected 1536 dimensions, got %d", len(emb))
	}
}

func TestGenerateEmbedding_DimensionMismatch(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		resp := embeddingResponse{
			Data: []struct {
				Embedding []float64 `json:"embedding"`
				Index     int       `json:"index"`
			}{
				{Embedding: []float64{0.1, 0.2, 0.3}, Index: 0},
			},
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	client := NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	_, err := client.GenerateEmbedding(context.Background(), "hello")
	if err == nil {
		t.Fatal("expected dimension mismatch error")
	}
}

func TestGenerateEmbedding_RetryOn429(t *testing.T) {
	attempts := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 3 {
			w.WriteHeader(http.StatusTooManyRequests)
			w.Write([]byte(`{"error":"rate limit"}`))
			return
		}
		resp := embeddingResponse{
			Data: []struct {
				Embedding []float64 `json:"embedding"`
				Index     int       `json:"index"`
			}{
				{Embedding: make([]float64, 1536), Index: 0},
			},
		}
		for i := range resp.Data[0].Embedding {
			resp.Data[0].Embedding[i] = 0.5
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	client := NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	emb, err := client.GenerateEmbedding(context.Background(), "hello")
	if err != nil {
		t.Fatalf("unexpected error after retry: %v", err)
	}
	if len(emb) != 1536 {
		t.Fatalf("expected 1536 dimensions, got %d", len(emb))
	}
	if attempts != 3 {
		t.Fatalf("expected 3 attempts (2 retries), got %d", attempts)
	}
}

func TestGenerateEmbedding_RetryOn500(t *testing.T) {
	attempts := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		if attempts < 2 {
			w.WriteHeader(http.StatusInternalServerError)
			w.Write([]byte(`{"error":"server error"}`))
			return
		}
		resp := embeddingResponse{
			Data: []struct {
				Embedding []float64 `json:"embedding"`
				Index     int       `json:"index"`
			}{
				{Embedding: make([]float64, 1536), Index: 0},
			},
		}
		for i := range resp.Data[0].Embedding {
			resp.Data[0].Embedding[i] = 0.5
		}
		json.NewEncoder(w).Encode(resp)
	}))
	defer srv.Close()

	client := NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	emb, err := client.GenerateEmbedding(context.Background(), "hello")
	if err != nil {
		t.Fatalf("unexpected error after retry: %v", err)
	}
	if len(emb) != 1536 {
		t.Fatalf("expected 1536 dimensions, got %d", len(emb))
	}
}

func TestGenerateEmbedding_ExhaustRetries(t *testing.T) {
	attempts := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintf(w, `{"error":"down"}`)
	}))
	defer srv.Close()

	client := NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	_, err := client.GenerateEmbedding(context.Background(), "hello")
	if err == nil {
		t.Fatal("expected error after exhausting retries")
	}
	if attempts != 4 { // initial + 3 retries
		t.Fatalf("expected 4 total attempts, got %d", attempts)
	}
}

func TestGenerateEmbedding_NoRetryOn400(t *testing.T) {
	attempts := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		attempts++
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprintf(w, `{"error":"bad request"}`)
	}))
	defer srv.Close()

	client := NewEmbeddingClient("test-key", srv.URL, "text-embedding-3-small")
	_, err := client.GenerateEmbedding(context.Background(), "hello")
	if err == nil {
		t.Fatal("expected error on 400")
	}
	if attempts != 1 {
		t.Fatalf("expected 1 attempt, got %d", attempts)
	}
}

func TestGenerateEmbedding_MockNoAPIKey(t *testing.T) {
	client := NewEmbeddingClient("", "", "")
	emb, err := client.GenerateEmbedding(context.Background(), "hello")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(emb) != 1536 {
		t.Fatalf("expected 1536 dimensions, got %d", len(emb))
	}
}
