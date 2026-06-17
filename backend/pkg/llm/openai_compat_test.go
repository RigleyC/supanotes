package llm

import "testing"

func TestNewOpenAICompatClientConfiguresHTTPTimeout(t *testing.T) {
	client := NewOpenAICompatClient("test-key", "https://example.com/v1/chat/completions", "test-model")

	compatClient, ok := client.(*openAICompatClient)
	if !ok {
		t.Fatalf("expected *openAICompatClient, got %T", client)
	}

	if compatClient.client.Timeout == 0 {
		t.Fatal("expected OpenAI-compatible HTTP client to have a finite timeout")
	}
}
