with open('internal/auth/service_test.go', 'r') as f:
    content = f.read()

mock_methods = """
func (m *mockQuerier) CreateRoutine(ctx context.Context, arg sqlcgen.CreateRoutineParams) (sqlcgen.Routine, error) { return sqlcgen.Routine{}, nil }
func (m *mockQuerier) UpdateRoutine(ctx context.Context, arg sqlcgen.UpdateRoutineParams) (sqlcgen.Routine, error) { return sqlcgen.Routine{}, nil }
func (m *mockQuerier) GetRoutinesByUser(ctx context.Context, userID pgtype.UUID) ([]sqlcgen.Routine, error) { return nil, nil }
func (m *mockQuerier) GetEnabledRoutines(ctx context.Context) ([]sqlcgen.GetEnabledRoutinesRow, error) { return nil, nil }
func (m *mockQuerier) CreateRoutineLog(ctx context.Context, arg sqlcgen.CreateRoutineLogParams) (sqlcgen.RoutineLog, error) { return sqlcgen.RoutineLog{}, nil }
func (m *mockQuerier) GetRoutineLogsByUser(ctx context.Context, arg sqlcgen.GetRoutineLogsByUserParams) ([]sqlcgen.RoutineLog, error) { return nil, nil }
func (m *mockQuerier) CleanupOldMessages(ctx context.Context) error { return nil }

func testConfig() *config.Config {
"""
content = content.replace('func testConfig() *config.Config {', mock_methods)

with open('internal/auth/service_test.go', 'w') as f:
    f.write(content)
