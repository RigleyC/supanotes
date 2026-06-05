import os

# fix service.go
with open('internal/routines/service.go', 'r') as f:
    content = f.read()

content = content.replace('"github.com/RigleyC/supanotes/internal/agent"\n\t', '')
content = content.replace('agentCtxBldr *agent.ContextBuilder', 'agentCtxBldr ContextBuilder')

interface_def = """type ContextBuilder interface {
	BuildForRoutine(ctx context.Context, userID pgtype.UUID, routineType string) (string, error)
}

"""
idx = content.find('type Service struct {')
content = content[:idx] + interface_def + content[idx:]

with open('internal/routines/service.go', 'w') as f:
    f.write(content)

# fix runner.go
with open('internal/routines/runner.go', 'r') as f:
    content = f.read()

content = content.replace('"github.com/RigleyC/supanotes/internal/agent"\n\t', '')
content = content.replace('agentCtxBldr *agent.ContextBuilder', 'agentCtxBldr ContextBuilder')

with open('internal/routines/runner.go', 'w') as f:
    f.write(content)
