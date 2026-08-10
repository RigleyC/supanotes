package attachments

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/stretchr/testify/require"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

func TestDeliveryServiceAllowsAuthenticatedNoteViewers(t *testing.T) {
	t.Parallel()

	for _, permission := range []string{"owner", "edit", "view"} {
		permission := permission
		t.Run(permission, func(t *testing.T) {
			t.Parallel()

			repo := &deliveryRepo{
				permission: permission,
				attachment: deliveryAttachment(),
			}
			storage := &deliveryStorage{}
			svc := NewDeliveryService(repo, storage)

			delivery, err := svc.Authenticated(
				context.Background(),
				testUUID(2),
				testUUID(3),
			)

			require.NoError(t, err)
			require.Equal(t, "report.pdf", delivery.Filename)
			require.Equal(t, "application/pdf", delivery.MimeType)
			require.Equal(t, "attachments/note/report.pdf", storage.openedKey)
			require.NoError(t, delivery.Body.Close())
		})
	}
}

func TestDeliveryServiceRejectsAuthenticatedPermissionWithoutHidingStorageErrors(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		name       string
		permission string
		storageErr error
		wantErr    error
	}{
		{name: "no permission", permission: "none", wantErr: ErrAttachmentForbidden},
		{name: "storage failure", permission: "view", storageErr: errStorageDown, wantErr: errStorageDown},
	} {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()

			repo := &deliveryRepo{permission: tc.permission, attachment: deliveryAttachment()}
			storage := &deliveryStorage{openErr: tc.storageErr}
			svc := NewDeliveryService(repo, storage)

			_, err := svc.Authenticated(context.Background(), testUUID(2), testUUID(3))

			require.ErrorIs(t, err, tc.wantErr)
			if tc.storageErr != nil {
				require.NotErrorIs(t, err, ErrAttachmentNotFound)
			}
		})
	}
}

func TestDeliveryServicePublicAccessRequiresAttachmentToBelongToShareNote(t *testing.T) {
	t.Parallel()

	repo := &deliveryRepo{attachment: deliveryAttachment()}
	svc := NewDeliveryService(repo, &deliveryStorage{})

	_, err := svc.Public(context.Background(), testUUID(9), testUUID(3))

	require.ErrorIs(t, err, ErrAttachmentNotFound)
}

func TestDeliveryServicePublicAccessStreamsPrivateObject(t *testing.T) {
	t.Parallel()

	repo := &deliveryRepo{attachment: deliveryAttachment()}
	storage := &deliveryStorage{}
	svc := NewDeliveryService(repo, storage)

	delivery, err := svc.Public(context.Background(), testUUID(1), testUUID(3))

	require.NoError(t, err)
	require.Equal(t, "private content", readDeliveryBody(t, delivery.Body))
	require.Equal(t, "attachments/note/report.pdf", storage.openedKey)
}

var errStorageDown = errors.New("object storage unavailable")

type deliveryRepo struct {
	permission string
	attachment sqlcgen.Attachment
	getErr     error
}

func (r *deliveryRepo) CheckNotePermission(context.Context, pgtype.UUID, pgtype.UUID) (string, error) {
	return r.permission, nil
}

func (r *deliveryRepo) Insert(context.Context, pgtype.UUID, string, string, string, int64) (sqlcgen.Attachment, error) {
	panic("not used")
}

func (r *deliveryRepo) ListByNote(context.Context, pgtype.UUID) ([]sqlcgen.Attachment, error) {
	panic("not used")
}

func (r *deliveryRepo) GetByID(context.Context, pgtype.UUID) (sqlcgen.Attachment, error) {
	if r.getErr != nil {
		return sqlcgen.Attachment{}, r.getErr
	}
	return r.attachment, nil
}

func (r *deliveryRepo) Delete(context.Context, pgtype.UUID) error {
	panic("not used")
}

type deliveryStorage struct {
	openedKey string
	openErr   error
}

func (s *deliveryStorage) Upload(context.Context, string, io.Reader, string, int64) (StoredObject, error) {
	panic("not used")
}

func (s *deliveryStorage) Open(_ context.Context, key string) (io.ReadCloser, error) {
	s.openedKey = key
	if s.openErr != nil {
		return nil, s.openErr
	}
	return io.NopCloser(strings.NewReader("private content")), nil
}

func (s *deliveryStorage) Delete(context.Context, string) error {
	panic("not used")
}

func deliveryAttachment() sqlcgen.Attachment {
	return sqlcgen.Attachment{
		ID:         testUUID(3),
		NoteID:     testUUID(1),
		Filename:   "report.pdf",
		StorageKey: "attachments/note/report.pdf",
		MimeType:   "application/pdf",
		SizeBytes:  15,
	}
}

func readDeliveryBody(t *testing.T, body io.ReadCloser) string {
	t.Helper()
	defer body.Close()
	contents, err := io.ReadAll(body)
	require.NoError(t, err)
	return string(contents)
}
