package mcpapp

// CurrentToolNames is the MCP contract inventory for the current note product.
// Keep this list limited to capabilities that exist in the retained app.
var CurrentToolNames = []string{
	"list_notes",
	"get_note",
	"create_note",
	"update_note",
	"delete_note",
	"list_tasks",
	"create_task",
	"update_task",
	"complete_task",
	"reopen_task",
	"delete_task",
	"get_note_document",
	"list_note_operations",
}

var removedToolNames = []string{
	"list_memories",
	"create_memory",
	"delete_memory",
	"list_tags",
	"create_tag",
	"add_tag_to_note",
	"remove_tag_from_note",
	"get_soul",
	"update_soul",
}
