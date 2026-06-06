package notifications

import (
	"context"
	"strings"

	"firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/rs/zerolog/log"
	"google.golang.org/api/option"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
	"github.com/RigleyC/supanotes/pkg/uid"
)

// Sender is the contract the rest of the app uses to push
// notifications. Implementations are responsible for fan-out to
// every device a user has registered.
type Sender interface {
	Send(ctx context.Context, userID string, title, body string) error
}

// TruncateBody keeps notification bodies under the 200-char limit
// that the original spec calls out. Exposed for tests.
func TruncateBody(body string, max int) string {
	body = strings.TrimSpace(body)
	if len(body) <= max {
		return body
	}
	return body[:max-1] + "…"
}

// NewApp builds a Firebase app (or returns a noop sender if creds
// aren't configured, so dev environments don't crash on startup).
func NewApp(credentialsFile string) (*firebase.App, error) {
	opts := []option.ClientOption{}
	if credentialsFile != "" {
		opts = append(opts, option.WithCredentialsFile(credentialsFile))
	}
	return firebase.NewApp(context.Background(), nil, opts...)
}

// FCMSender sends a single message to a single device token. Useful
// for tests and as a building block.
type FCMSender struct {
	client *messaging.Client
}

func NewFCMSender(credentialsFile string) (*FCMSender, error) {
	app, err := NewApp(credentialsFile)
	if err != nil {
		return nil, err
	}
	client, err := app.Messaging(context.Background())
	if err != nil {
		return nil, err
	}
	return &FCMSender{client: client}, nil
}

func (f *FCMSender) Send(ctx context.Context, token, title, body string) error {
	_, err := f.client.Send(ctx, &messaging.Message{
		Notification: &messaging.Notification{Title: title, Body: TruncateBody(body, 200)},
		Token:        token,
	})
	return err
}

// NoopSender is the default when Firebase isn't configured. It
// satisfies Sender without ever contacting Google.
type NoopSender struct{}

func (NoopSender) Send(_ context.Context, _ string, _ string, _ string) error {
	return nil
}

// MultiDeviceSender is the Sender implementation the rest of the
// backend uses: it resolves every device token the user has
// registered and dispatches a message to each one. Failures on
// individual tokens are logged but don't stop the loop.
type MultiDeviceSender struct {
	client *messaging.Client
	q      sqlcgen.Querier
}

// NewMultiDeviceSender returns a Sender that fans out to all
// devices a user has registered. If credentialsFile is empty, the
// returned sender is a no-op for the actual HTTP call but still
// queries the token table — useful in dev to confirm wiring.
func NewMultiDeviceSender(credentialsFile string, q sqlcgen.Querier) (*MultiDeviceSender, error) {
	if credentialsFile == "" {
		return &MultiDeviceSender{client: nil, q: q}, nil
	}
	app, err := NewApp(credentialsFile)
	if err != nil {
		return nil, err
	}
	client, err := app.Messaging(context.Background())
	if err != nil {
		return nil, err
	}
	return &MultiDeviceSender{client: client, q: q}, nil
}

func (m *MultiDeviceSender) Send(ctx context.Context, userID, title, body string) error {
	uidVal, err := uid.UUIDFromString(userID)
	if err != nil {
		return err
	}
	tokens, err := m.q.ListDeviceTokensByUser(ctx, uidVal)
	if err != nil {
		return err
	}
	if len(tokens) == 0 {
		log.Debug().Str("user_id", userID).Msg("no device tokens registered; skipping push")
		return nil
	}
	if m.client == nil {
		log.Debug().Str("user_id", userID).Int("count", len(tokens)).Msg("FCM not configured; would have sent")
		return nil
	}

	body = TruncateBody(body, 200)

	for _, t := range tokens {
		_, err := m.client.Send(ctx, &messaging.Message{
			Notification: &messaging.Notification{Title: title, Body: body},
			Token:        t.Token,
		})
		if err != nil {
			log.Error().Err(err).Str("user_id", userID).Str("platform", t.Platform).Msg("fcm send failed for one device")
		}
	}
	return nil
}
