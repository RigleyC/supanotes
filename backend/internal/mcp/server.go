package mcpapp

import (
	"fmt"

	"github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/RigleyC/supanotes/internal/attachments"
	"github.com/RigleyC/supanotes/internal/noteoperations"
	"github.com/RigleyC/supanotes/internal/notes"
	"github.com/RigleyC/supanotes/internal/settings"
	"github.com/RigleyC/supanotes/internal/shares"
	"github.com/RigleyC/supanotes/internal/tasks"
)

type ServerDependencies struct {
	Security         SecurityStore
	Notes            *notes.Service
	Tasks            *tasks.Service
	DocumentReader   noteoperations.DocumentReader
	DocumentCommands noteoperations.DocumentCommandService
	Attachments      attachments.Service
	Shares           *shares.Service
	Settings         *settings.Service
}

func (d ServerDependencies) Validate() error {
	missing := ""
	if d.Security == nil {
		missing = "security"
	} else if d.Notes == nil {
		missing = "notes"
	} else if d.Tasks == nil {
		missing = "tasks"
	} else if d.DocumentReader == nil {
		missing = "document reader"
	} else if d.DocumentCommands == nil {
		missing = "document commands"
	} else if d.Attachments == nil {
		missing = "attachments"
	} else if d.Shares == nil {
		missing = "shares"
	} else if d.Settings == nil {
		missing = "settings"
	}
	if missing != "" {
		return fmt.Errorf("MCP server dependency is not configured: %s", missing)
	}
	return nil
}

func NewServer(deps ServerDependencies) *mcp.Server {
	if err := deps.Validate(); err != nil {
		panic(err)
	}
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "SupaNotes MCP",
		Version: "1.0.0",
	}, nil)

	RegisterTools(server, deps)

	return server
}
