package mcpapp

import (
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/attachments"
	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/settings"
	"github.com/RigleyC/supanotes/internal/shares"
	"github.com/RigleyC/supanotes/internal/tasks"
)

func NewServer(
	security SecurityStore,
	notesSvc *notes.Service,
	tasksSvc *tasks.Service,
	documentReader noteoperations.DocumentReader,
	documentCommands noteoperations.DocumentCommandService,
	attachmentsSvc attachments.Service,
	sharesSvc *shares.Service,
	settingsSvc *settings.Service,
) *mcp.Server {
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "SupaNotes MCP",
		Version: "1.0.0",
	}, nil)

	RegisterTools(server, security, notesSvc, tasksSvc, documentReader, documentCommands, attachmentsSvc, sharesSvc, settingsSvc)

	return server
}
