package mcpapp

import (
	"testing"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"github.com/stretchr/testify/assert"
)

func TestRegisterTools(t *testing.T) {
	server := mcp.NewServer(&mcp.Implementation{Name: "Test"}, nil)
	RegisterTools(server, nil, nil, nil, nil, nil)
	assert.NotNil(t, server)
}
