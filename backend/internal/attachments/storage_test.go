package attachments

import (
	"context"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestNoopStorageNeverReportsSuccessfulLifecycleOperations(t *testing.T) {
	t.Parallel()

	storage := &noopStorage{}

	_, err := storage.Upload(context.Background(), "attachments/key", strings.NewReader("content"), "text/plain", 7)
	require.ErrorIs(t, err, ErrStorageUnavailable)

	require.ErrorIs(t, storage.Delete(context.Background(), "attachments/key"), ErrStorageUnavailable)

	_, err = storage.Open(context.Background(), "attachments/key")
	require.ErrorIs(t, err, ErrStorageUnavailable)
}
