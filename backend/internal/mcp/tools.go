package mcpapp

import (
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/noteoperations"
)

func RegisterTools(
	server *mcp.Server,
	deps ServerDependencies,
) {
	if deps.Security == nil {
		panic("MCP security dependency is required")
	}
	security := deps.Security
	addAttachmentTools(server, security, deps.Attachments, deps.DocumentReader)
	addSharingAndSettingsTools(server, security, deps.Shares, deps.Settings)
	addBlockMutationTool(server, security, toolCreateBlock, noteoperations.KindCreateBlock, deps.DocumentCommands, false)
	addBlockMutationTool(server, security, toolCreateTaskBlock, noteoperations.KindCreateBlock, deps.DocumentCommands, false)
	addBlockMutationTool(server, security, toolUpdateBlockText, noteoperations.KindTextDelta, deps.DocumentCommands, false)
	addBlockMutationTool(server, security, toolMoveBlock, noteoperations.KindMoveBlock, deps.DocumentCommands, false)
	addBlockMutationTool(server, security, toolDeleteBlock, noteoperations.KindDeleteBlock, deps.DocumentCommands, true)
	addBlockMutationTool(server, security, toolSetBlockType, noteoperations.KindSetBlockType, deps.DocumentCommands, false)
	addBlockMutationTool(server, security, toolSetBlockMetadata, noteoperations.KindSetBlockMetadata, deps.DocumentCommands, false)
	addBlockMutationTool(server, security, toolUpdateTaskMetadata, noteoperations.KindSetBlockMetadata, deps.DocumentCommands, false)
	addTaskOccurrenceTool(server, security, toolCompleteTaskOccurrence, deps.DocumentCommands, false)
	addTaskOccurrenceTool(server, security, toolReopenTaskOccurrence, deps.DocumentCommands, true)
	addNoteTools(server, security, deps.Notes, deps.DocumentReader)
	addTaskTools(server, security, deps.Tasks)
}
