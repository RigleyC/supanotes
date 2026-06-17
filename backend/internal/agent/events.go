package agent

type EventType string

const (
	EventMessageStarted       EventType = "message_started"
	EventContentDelta         EventType = "content_delta"
	EventToolStarted          EventType = "tool_started"
	EventToolFinished         EventType = "tool_finished"
	EventToolFailed           EventType = "tool_failed"
	EventMessageFinished      EventType = "message_finished"
	EventError                EventType = "error"
	EventConfirmationRequired EventType = "confirmation_required"
)

type StreamEvent struct {
	SessionID string      `json:"session_id"`
	MessageID string      `json:"message_id"`
	Sequence  int         `json:"sequence"`
	Type      EventType   `json:"type"`
	Payload   interface{} `json:"payload"`
}

type ContentDeltaPayload struct {
	Delta string `json:"delta"`
}

type ToolActivityPayload struct {
	Name  string `json:"name"`
	Label string `json:"label"`
}

type ToolFailedPayload struct {
	Name    string `json:"name"`
	Label   string `json:"label"`
	Message string `json:"message"`
}

type MessageFinishedPayload struct {
	Content string `json:"content"`
}

type ErrorPayload struct {
	Message string `json:"message"`
}

type ConfirmationRequiredPayload struct {
	ToolName string `json:"tool_name"`
	Label    string `json:"label"`
	ArgsJSON string `json:"args_json"`
}

type StreamEventWriter struct {
	sessionID string
	messageID string
	sequence  int
}

func NewStreamEventWriter(sessionID, messageID string) *StreamEventWriter {
	return &StreamEventWriter{sessionID: sessionID, messageID: messageID}
}

func (w *StreamEventWriter) Event(typ EventType, payload interface{}) StreamEvent {
	w.sequence++
	return StreamEvent{
		SessionID: w.sessionID,
		MessageID: w.messageID,
		Sequence:  w.sequence,
		Type:      typ,
		Payload:   payload,
	}
}
