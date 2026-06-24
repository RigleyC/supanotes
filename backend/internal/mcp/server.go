package mcpapp

import (
	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/memories"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/soul"
	"github.com/RigleyC/supanotes/internal/tags"
	"github.com/RigleyC/supanotes/internal/tasks"
)

func NewServer(
	notesSvc *notes.Service,
	tasksSvc *tasks.Service,
	memoriesSvc *memories.Service,
	tagsSvc *tags.Service,
	soulSvc *soul.Service,
) *mcp.Server {
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "SupaNotes MCP",
		Version: "1.0.0",
	}, nil)

	RegisterTools(server, notesSvc, tasksSvc, memoriesSvc, tagsSvc, soulSvc)

	return server
}
