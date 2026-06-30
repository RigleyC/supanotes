package agent

import (
	"context"
	"errors"
	"testing"

	"github.com/RigleyC/supanotes/pkg/llm"
)

type stubLLMClient struct {
	content string
}

func (s *stubLLMClient) Complete(ctx context.Context, req llm.Request) (*llm.Response, error) {
	return &llm.Response{Content: s.content}, nil
}

func (s *stubLLMClient) CompleteStream(ctx context.Context, req llm.Request, onToken func(string) error) (*llm.Response, error) {
	return &llm.Response{Content: s.content}, nil
}

type errorStubLLMClient struct{}

func (s *errorStubLLMClient) Complete(ctx context.Context, req llm.Request) (*llm.Response, error) {
	return nil, errors.New("llm error")
}

func (s *errorStubLLMClient) CompleteStream(ctx context.Context, req llm.Request, onToken func(string) error) (*llm.Response, error) {
	return nil, errors.New("llm error")
}

func TestIntentClassifier(t *testing.T) {
	tests := []struct {
		name     string
		content  string
		want     Intent
		wantErr  bool
		stubType string // "ok" or "error"
	}{
		{
			name:    "daily_summary",
			content: "DailySummary",
			want:    IntentDailySummary,
			stubType: "ok",
		},
		{
			name:    "search_knowledge",
			content: "SearchKnowledge",
			want:    IntentSearchKnowledge,
			stubType: "ok",
		},
		{
			name:    "task_management",
			content: "TaskManagement",
			want:    IntentTaskManagement,
			stubType: "ok",
		},
		{
			name:     "unrecognized_intent",
			content:  "UnknownIntent",
			want:     IntentGeneralChat,
			stubType: "ok",
		},
		{
			name:     "llm_error",
			content:  "",
			want:     IntentGeneralChat,
			wantErr:  true,
			stubType: "error",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var classifier *IntentClassifier
			if tt.stubType == "error" {
				classifier = NewIntentClassifier(&errorStubLLMClient{})
			} else {
				classifier = NewIntentClassifier(&stubLLMClient{content: tt.content})
			}
			intent, err := classifier.Classify(context.Background(), "test message")
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if intent != IntentGeneralChat {
					t.Errorf("expected GeneralChat on error, got %v", intent)
				}
				return
			}
			if err != nil {
				t.Fatalf("Classify failed: %v", err)
			}
			if intent != tt.want {
				t.Errorf("expected %v, got %v", tt.want, intent)
			}
		})
	}
}
