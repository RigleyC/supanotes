package agent

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

type fakeYDocIngest struct {
	applied bool
}

func (f *fakeYDocIngest) ApplyNodeMutation(_ context.Context, _ string, _ []byte) error {
	f.applied = true
	return nil
}

func TestYjsMutationService_DelegatesToYDocService(t *testing.T) {
	fake := &fakeYDocIngest{}
	svc := NewYjsMutationService(fake)
	require.NoError(t, svc.WriteNodeMutation(context.Background(), "123e4567-e89b-12d3-a456-426614174000", []byte{1, 2, 3}))
	assert.True(t, fake.applied, "YjsMutationService must call YDocService.ApplyNodeMutation")
}
