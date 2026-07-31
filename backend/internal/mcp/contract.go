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
	"get_note_document",
	"list_note_operations",
	"create_block",
	"update_block_text",
	"move_block",
	"delete_block",
	"set_block_type",
	"set_block_metadata",
	"create_task_block",
	"update_task_metadata",
	"complete_task_occurrence",
	"reopen_task_occurrence",
	"upload_attachment",
	"list_note_attachments",
	"delete_attachment",
	"list_note_shares",
	"share_note",
	"remove_note_share",
	"get_user_settings",
	"update_user_settings",
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
