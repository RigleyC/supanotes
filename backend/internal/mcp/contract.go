package mcpapp

const (
	toolListNotes              = "list_notes"
	toolGetNote                = "get_note"
	toolCreateNote             = "create_note"
	toolUpdateNote             = "update_note"
	toolDeleteNote             = "delete_note"
	toolListTasks              = "list_tasks"
	toolGetNoteDocument        = "get_note_document"
	toolListNoteOperations     = "list_note_operations"
	toolCreateBlock            = "create_block"
	toolUpdateBlockText        = "update_block_text"
	toolMoveBlock              = "move_block"
	toolDeleteBlock            = "delete_block"
	toolSetBlockType           = "set_block_type"
	toolSetBlockMetadata       = "set_block_metadata"
	toolCreateTaskBlock        = "create_task_block"
	toolUpdateTaskMetadata     = "update_task_metadata"
	toolCompleteTaskOccurrence = "complete_task_occurrence"
	toolReopenTaskOccurrence   = "reopen_task_occurrence"
	toolUploadAttachment       = "upload_attachment"
	toolListNoteAttachments    = "list_note_attachments"
	toolDeleteAttachment       = "delete_attachment"
	toolListNoteShares         = "list_note_shares"
	toolShareNote              = "share_note"
	toolRemoveNoteShare        = "remove_note_share"
	toolGetUserSettings        = "get_user_settings"
	toolUpdateUserSettings     = "update_user_settings"
)

// CurrentToolNames is the MCP contract inventory for the current note product.
// Keep this list limited to capabilities that exist in the retained app.
var CurrentToolNames = []string{
	toolListNotes, toolGetNote, toolCreateNote, toolUpdateNote, toolDeleteNote,
	toolListTasks, toolGetNoteDocument, toolListNoteOperations,
	toolCreateBlock, toolUpdateBlockText, toolMoveBlock, toolDeleteBlock,
	toolSetBlockType, toolSetBlockMetadata, toolCreateTaskBlock, toolUpdateTaskMetadata,
	toolCompleteTaskOccurrence, toolReopenTaskOccurrence,
	toolUploadAttachment, toolListNoteAttachments, toolDeleteAttachment,
	toolListNoteShares, toolShareNote, toolRemoveNoteShare,
	toolGetUserSettings, toolUpdateUserSettings,
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
