with open('internal/routines/runner.go', 'r') as f:
    content = f.read()
content = content.replace('"github.com/jackc/pgx/v5/pgtype"\n\t', '')
content = content.replace('*llm.Factory', 'llm.Factory')
content = content.replace('llm.TaskAgentic', 'llm.TaskTypeAgentic')
with open('internal/routines/runner.go', 'w') as f:
    f.write(content)

with open('internal/routines/service.go', 'r') as f:
    content = f.read()
content = content.replace('*llm.Factory', 'llm.Factory')
content = content.replace('llm.TaskAgentic', 'llm.TaskTypeAgentic')
with open('internal/routines/service.go', 'w') as f:
    f.write(content)
