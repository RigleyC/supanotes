with open('cmd/server/main.go', 'r') as f:
    content = f.read()

content = content.replace('"github.com/RigleyC/supanotes/internal/tasks"', '"github.com/RigleyC/supanotes/internal/tasks"\n\t"github.com/RigleyC/supanotes/internal/routines"\n\t"github.com/RigleyC/supanotes/pkg/llm"')

old_agent_block = """	// Agent Loop
	agentRepo := agent.NewRepository(queries)
	agentCtxBldr := agent.NewContextBuilder(queries, tasksSvc)
	agentTools := agent.NewToolRegistry(queries, notesSvc, tasksSvc, memoriesSvc)
	llmFactory := llm.NewFactory(cfg)
	agentLoop := agent.NewLoop(agentRepo, llmFactory, agentCtxBldr, agentTools)
	agentH := agent.NewHandler(agentLoop, agentRepo)
	protected.POST("/agent/chat", agentH.Chat)
	protected.GET("/agent/messages", agentH.ListMessages)
	protected.DELETE("/agent/messages", agentH.DeleteMessages)"""

new_agent_block = """	// LLM Factory
	llmFactory := llm.NewFactory(cfg)

	// Agent Context Builder
	agentCtxBldr := agent.NewContextBuilder(queries, tasksSvc)

	// Routines
	routinesRepo := routines.NewRepository(queries)
	routinesSvc := routines.NewService(routinesRepo, agentCtxBldr, llmFactory)
	routinesH := routines.NewHandler(routinesSvc)
	routines.RegisterRoutes(protected, routinesH)

	routinesRunner := routines.NewRunner(routinesRepo, agentCtxBldr, llmFactory)
	routinesRunner.Start()

	// Agent Loop
	agentRepo := agent.NewRepository(queries)
	agentTools := agent.NewToolRegistry(queries, notesSvc, tasksSvc, memoriesSvc, routinesSvc)
	agentLoop := agent.NewLoop(agentRepo, llmFactory, agentCtxBldr, agentTools)
	agentH := agent.NewHandler(agentLoop, agentRepo)
	protected.POST("/agent/chat", agentH.Chat)
	protected.GET("/agent/messages", agentH.ListMessages)
	protected.DELETE("/agent/messages", agentH.DeleteMessages)"""

content = content.replace(old_agent_block, new_agent_block)

with open('cmd/server/main.go', 'w') as f:
    f.write(content)
