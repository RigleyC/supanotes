package mcpapp

var noParamSchema = map[string]any{"type": "object", "properties": map[string]any{}}

var listNotesSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"limit":             map[string]any{"type": "integer", "description": "Maximum number of notes to return (1-100)"},
		"cursor_updated_at": map[string]any{"type": "string", "description": "RFC3339 cursor timestamp"},
		"cursor_id":         map[string]any{"type": "string", "description": "Cursor note ID, required with cursor_updated_at"},
	},
}

var noteRevisionSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"note_id":        map[string]any{"type": "string", "description": "Note ID"},
		"after_revision": map[string]any{"type": "integer", "minimum": 0, "description": "Return operations after this revision"},
	},
	"required": []any{"note_id"},
}

var blockMutationSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"note_id":       map[string]any{"type": "string", "description": "Note ID"},
		"block_id":      map[string]any{"type": "string", "description": "Block ID"},
		"base_revision": map[string]any{"type": "integer", "minimum": 0, "description": "Document revision used as the operation base"},
		"payload":       map[string]any{"type": "object", "description": "Operation-specific payload"},
		"operation_id":  map[string]any{"type": "string", "description": "Optional UUID used for idempotent retries"},
		"client_id":     map[string]any{"type": "string", "description": "Optional caller identifier"},
	},
	"required": []any{"note_id", "base_revision"},
}

var destructiveBlockMutationSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"note_id":         map[string]any{"type": "string", "description": "Note ID"},
		"block_id":        map[string]any{"type": "string", "description": "Block ID"},
		"base_revision":   map[string]any{"type": "integer", "minimum": 0, "description": "Document revision used as the operation base"},
		"payload":         map[string]any{"type": "object", "description": "Operation-specific payload"},
		"operation_id":    map[string]any{"type": "string", "description": "Optional UUID used for idempotent retries"},
		"client_id":       map[string]any{"type": "string", "description": "Optional caller identifier"},
		"confirmation_id": map[string]any{"type": "string", "description": "One-time confirmation ID"},
	},
	"required": []any{"note_id", "base_revision"},
}

var taskOccurrenceSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"note_id":       map[string]any{"type": "string"},
		"block_id":      map[string]any{"type": "string"},
		"base_revision": map[string]any{"type": "integer", "minimum": 0},
		"scheduled_at":  map[string]any{"type": "string", "description": "Scheduled occurrence timestamp"},
		"completed_at":  map[string]any{"type": "string", "description": "Completion timestamp; omit to reopen"},
		"operation_id":  map[string]any{"type": "string"},
	},
	"required": []any{"note_id", "block_id", "base_revision", "scheduled_at"},
}

var attachmentUploadSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"note_id":        map[string]any{"type": "string"},
		"filename":       map[string]any{"type": "string"},
		"content_base64": map[string]any{"type": "string", "description": "Base64 file content"},
	},
	"required": []any{"note_id", "filename", "content_base64"},
}

var attachmentDeleteSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"attachment_id":   map[string]any{"type": "string"},
		"confirmation_id": map[string]any{"type": "string", "description": "One-time confirmation ID"},
	},
	"required": []any{"attachment_id"},
}

var idParamSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"id": map[string]any{
			"type":        "string",
			"description": "ID",
		},
	},
	"required": []any{"id"},
}

var destructiveIDSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"id":              map[string]any{"type": "string", "description": "ID"},
		"confirmation_id": map[string]any{"type": "string", "description": "One-time confirmation ID"},
	},
	"required": []any{"id"},
}

var noteContentSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"content": map[string]any{
			"type":        "string",
			"description": "Note content",
		},
	},
	"required": []any{"content"},
}

var updateNoteSchema = map[string]any{
	"type": "object",
	"properties": map[string]any{
		"id": map[string]any{
			"type":        "string",
			"description": "Note ID",
		},
		"content": map[string]any{
			"type":        "string",
			"description": "Note content",
		},
	},
	"required": []any{"id", "content"},
}
