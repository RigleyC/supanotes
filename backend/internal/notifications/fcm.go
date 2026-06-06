package notifications

import (
	"context"

	"firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/rs/zerolog/log"
	"google.golang.org/api/option"

	"github.com/RigleyC/supanotes/internal/db/sqlcgen"
)

type Sender interface {
	Send(ctx context.Context, userID string, title, body string) error
}

type FCMSender struct {
	client *messaging.Client
}

func NewFCMSender(credentialsFile string) (*FCMSender, error) {
	opts := []option.ClientOption{}
	if credentialsFile != "" {
		opts = append(opts, option.WithCredentialsFile(credentialsFile))
	}

	app, err := firebase.NewApp(context.Background(), nil, opts...)
	if err != nil {
		return nil, err
	}

	client, err := app.Messaging(context.Background())
	if err != nil {
		return nil, err
	}

	return &FCMSender{client: client}, nil
}

func (f *FCMSender) Send(ctx context.Context, userID string, title, body string) error {
	msg := &messaging.Message{
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Token: userID,
	}

	_, err := f.client.Send(ctx, msg)
	if err != nil {
		log.Error().Err(err).Str("user_id", userID).Msg("fcm send failed")
		return err
	}
	return nil
}

type NoopSender struct{}

func (NoopSender) Send(_ context.Context, _ string, _ string, _ string) error {
	return nil
}

type MultiDeviceSender struct {
	client *messaging.Client
	q      sqlcgen.Querier
}

func NewMultiDeviceSender(client *messaging.Client, q sqlcgen.Querier) *MultiDeviceSender {
	return &MultiDeviceSender{client: client, q: q}
}

func (m *MultiDeviceSender) Send(ctx context.Context, userID string, title, body string) error {
	// For multi-device support: look up all device tokens for the user
	// and send to each one. For simplicity, use the Firebase topic approach.
	msg := &messaging.Message{
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Topic: "user_" + userID,
	}

	_, err := m.client.Send(ctx, msg)
	if err != nil {
		log.Error().Err(err).Str("user_id", userID).Msg("fcm topic send failed")
		return err
	}
	return nil
}
