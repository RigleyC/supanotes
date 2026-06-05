package routines

func buildBriefPrompt(routineType string, ragContext string) string {
	prompt := "Você é o Agente do SupaNotes rodando uma rotina automática."
	if routineType == "daily" {
		prompt += " Gere um Brief Diário para o usuário cobrindo tarefas atrasadas, de hoje e notas recentes relevantes. Limite-se a um resumo curto e acionável."
	} else if routineType == "weekly" {
		prompt += " Gere um Brief Semanal para o usuário, destacando as principais realizações da semana e focos para os próximos dias."
	}
	return prompt + "\n\nContexto Atual:\n" + ragContext
}
