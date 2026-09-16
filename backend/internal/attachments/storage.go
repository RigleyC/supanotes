package attachments

import (
	"context"
	"errors"
	"fmt"
	"io"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

var (
	ErrStorageUnavailable   = errors.New("attachment storage unavailable")
	ErrStorageInvalidObject = errors.New("attachment storage returned an invalid object")
	ErrStorageDelete        = errors.New("attachment storage delete failed")
)

type StorageOperationError struct {
	Operation string
	Err       error
}

func (e *StorageOperationError) Error() string {
	return fmt.Sprintf("attachment storage %s: %v", e.Operation, e.Err)
}

func (e *StorageOperationError) Unwrap() error {
	return e.Err
}

type StorageService interface {
	Upload(ctx context.Context, key string, r io.Reader, mimeType string, size int64) (StoredObject, error)
	Open(ctx context.Context, key string) (io.ReadCloser, error)
	Delete(ctx context.Context, key string) error
}

type StoredObject struct {
	Key string
}

type s3Storage struct {
	client *s3.Client
	bucket string
}

func NewS3Storage(endpoint, region, bucket, accessKey, secretKey string) (StorageService, error) {
	if bucket == "" {
		return &noopStorage{}, nil
	}
	cfg, err := awsconfig.LoadDefaultConfig(context.Background(),
		awsconfig.WithRegion(region),
		awsconfig.WithCredentialsProvider(
			credentials.NewStaticCredentialsProvider(accessKey, secretKey, ""),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("s3 config: %w", err)
	}
	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		if endpoint != "" {
			o.EndpointResolver = s3.EndpointResolverFromURL(endpoint)
			o.UsePathStyle = true
		}
	})
	return &s3Storage{client: client, bucket: bucket}, nil
}

func (s *s3Storage) Upload(ctx context.Context, key string, r io.Reader, mimeType string, size int64) (StoredObject, error) {
	uploader := manager.NewUploader(s.client)
	_, err := uploader.Upload(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(s.bucket),
		Key:           aws.String(key),
		ACL:           types.ObjectCannedACLPrivate,
		Body:          r,
		ContentType:   aws.String(mimeType),
		ContentLength: aws.Int64(size),
	})
	if err != nil {
		return StoredObject{}, &StorageOperationError{Operation: "upload", Err: err}
	}
	return StoredObject{Key: key}, nil
}

// Delete is intentionally idempotent: S3 DeleteObject succeeds when the key
// is already absent, which makes replaying a persisted cleanup intent safe.
func (s *s3Storage) Delete(ctx context.Context, key string) error {
	_, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return &StorageOperationError{Operation: "delete", Err: errors.Join(ErrStorageDelete, err)}
	}
	return nil
}

func (s *s3Storage) Open(ctx context.Context, key string) (io.ReadCloser, error) {
	result, err := s.client.GetObject(ctx, &s3.GetObjectInput{Bucket: aws.String(s.bucket), Key: aws.String(key)})
	if err != nil {
		return nil, &StorageOperationError{Operation: "open", Err: err}
	}
	if result == nil || result.Body == nil {
		return nil, &StorageOperationError{Operation: "open", Err: ErrStorageInvalidObject}
	}
	return result.Body, nil
}

type noopStorage struct{}

func (n *noopStorage) Upload(_ context.Context, _ string, _ io.Reader, _ string, _ int64) (StoredObject, error) {
	return StoredObject{}, fmt.Errorf("%w: set S3_BUCKET and related env vars", ErrStorageUnavailable)
}

func (n *noopStorage) Delete(_ context.Context, _ string) error {
	return fmt.Errorf("%w: set S3_BUCKET and related env vars", ErrStorageUnavailable)
}

func (n *noopStorage) Open(_ context.Context, _ string) (io.ReadCloser, error) {
	return nil, fmt.Errorf("%w: set S3_BUCKET and related env vars", ErrStorageUnavailable)
}
