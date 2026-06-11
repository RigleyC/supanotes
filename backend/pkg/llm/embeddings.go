package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"time"
)

const embeddingDim = 1536

type EmbeddingClient struct {
	apiKey     string
	baseURL    string
	model      string
	client     *http.Client
	maxRetries int
}

func NewEmbeddingClient(apiKey, baseURL, model string) *EmbeddingClient {
	if apiKey == "" {
		return &EmbeddingClient{client: &http.Client{}}
	}
	return &EmbeddingClient{
		apiKey:     apiKey,
		baseURL:    defaultIfEmpty(baseURL, "https://api.openai.com/v1/embeddings"),
		model:      defaultIfEmpty(model, "text-embedding-3-small"),
		client:     &http.Client{Timeout: 30 * time.Second},
		maxRetries: 3,
	}
}

type embeddingRequest struct {
	Model string   `json:"model"`
	Input []string `json:"input"`
}

type embeddingResponse struct {
	Data []struct {
		Embedding []float64 `json:"embedding"`
		Index     int       `json:"index"`
	} `json:"data"`
	Usage struct {
		PromptTokens int `json:"prompt_tokens"`
	} `json:"usage"`
}

func (c *EmbeddingClient) GenerateEmbedding(ctx context.Context, text string) ([]float64, error) {
	if c.apiKey == "" {
		return makeMockEmbedding(), nil
	}

	var lastErr error
	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		emb, err := c.generateOnce(ctx, text)
		if err == nil {
			if len(emb) != embeddingDim {
				return nil, fmt.Errorf("embeddings: unexpected dimension %d, expected %d", len(emb), embeddingDim)
			}
			return emb, nil
		}

		lastErr = err

		if !isRetryable(err) || attempt == c.maxRetries {
			break
		}

		backoff := time.Duration(1<<attempt) * time.Second
		jitter := time.Duration(rand.Intn(1000)) * time.Millisecond
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(backoff + jitter):
		}
	}

	return nil, fmt.Errorf("embeddings: failed after %d retries: %w", c.maxRetries, lastErr)
}

func (c *EmbeddingClient) generateOnce(ctx context.Context, text string) ([]float64, error) {
	body, err := json.Marshal(embeddingRequest{
		Model: c.model,
		Input: []string{text},
	})
	if err != nil {
		return nil, fmt.Errorf("embeddings: marshal: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL, bytes.NewReader(body))
	if err != nil {
		return nil, fmt.Errorf("embeddings: new req: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("embeddings: http: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("embeddings API error %d: %s", resp.StatusCode, string(respBody))
	}

	var parsed embeddingResponse
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return nil, fmt.Errorf("embeddings: decode: %w", err)
	}

	if len(parsed.Data) == 0 {
		return nil, fmt.Errorf("embeddings: empty response")
	}

	return parsed.Data[0].Embedding, nil
}

func makeMockEmbedding() []float64 {
	v := make([]float64, embeddingDim)
	for i := range v {
		v[i] = 0.01
	}
	return v
}
