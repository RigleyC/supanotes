package agent

type BudgetManager struct {
	currentIteration int
	maxIterations    int
}

func NewBudgetManager(maxIterations int) *BudgetManager {
	return &BudgetManager{
		maxIterations: maxIterations,
	}
}

func (b *BudgetManager) Advance() {
	b.currentIteration++
}

func (b *BudgetManager) CurrentIteration() int {
	return b.currentIteration
}

func (b *BudgetManager) MaxIterations() int {
	return b.maxIterations
}

func (b *BudgetManager) IsExhausted() bool {
	return b.currentIteration >= b.maxIterations
}

func (b *BudgetManager) NeedsWarning() bool {
	return b.currentIteration == b.maxIterations-3
}

func (b *BudgetManager) NeedsFinalWarning() bool {
	return b.currentIteration == b.maxIterations-1
}

func (b *BudgetManager) GetSystemPromptWarning() string {
	switch {
	case b.NeedsFinalWarning():
		return "\nSYSTEM INSTRUCTION: This is the absolute final iteration (14/15). Finish the task and summarize your response now.\n"
	case b.NeedsWarning():
		return "\nSYSTEM INSTRUCTION: You are approaching the iteration limit (12/15). Start preparing the final response.\n"
	default:
		return ""
	}
}
