package agent

import (
	"encoding/json"
	"testing"
)

func TestStreamEventEnvelopeMarshal(t *testing.T) {
	event := StreamEvent{
		SessionID: "session-1",
		MessageID: "message-1",
		Sequence:  7,
		Type:      EventContentDelta,
		Payload:   ContentDeltaPayload{Delta: "Oi"},
	}

	body, err := json.Marshal(event)
	if err != nil {
		t.Fatalf("marshal event: %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(body, &decoded); err != nil {
		t.Fatalf("decode event: %v", err)
	}

	if decoded["session_id"] != "session-1" {
		t.Fatalf("session_id: got %#v", decoded["session_id"])
	}
	if decoded["message_id"] != "message-1" {
		t.Fatalf("message_id: got %#v", decoded["message_id"])
	}
	if decoded["sequence"].(float64) != 7 {
		t.Fatalf("sequence: got %#v", decoded["sequence"])
	}
	if decoded["type"] != string(EventContentDelta) {
		t.Fatalf("type: got %#v", decoded["type"])
	}
	if decoded["payload"] == nil {
		t.Fatal("payload missing")
	}
}

func TestStreamEventWriterIncrementsSequence(t *testing.T) {
	writer := NewStreamEventWriter("session-1", "message-1")

	first := writer.Event(EventMessageStarted, map[string]string{"role": "assistant"})
	second := writer.Event(EventMessageFinished, MessageFinishedPayload{Content: "Pronto"})

	if first.Sequence != 1 {
		t.Fatalf("first sequence: want 1, got %d", first.Sequence)
	}
	if second.Sequence != 2 {
		t.Fatalf("second sequence: want 2, got %d", second.Sequence)
	}
}
