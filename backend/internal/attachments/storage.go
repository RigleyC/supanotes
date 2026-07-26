package attachments

import (
	"context"
	"fmt"
	"io"
	"net/url"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type StorageService interface {
	Upload(ctx context.Context, key string, r io.Reader, mimeType string, size int64) (StoredObject, error)
	Delete(ctx context.Context, key string) error
}

type StoredObject struct {
	Key       string
	PublicURL string
}

type s3Storage struct {
	client     *s3.Client
	bucket     string
	publicBase string
}

func NewS3Storage(endpoint, region, bucket, accessKey, secretKey, publicBase string) (StorageService, error) {
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
	return &s3Storage{client: client, bucket: bucket, publicBase: publicBase}, nil
}

func (s *s3Storage) Upload(ctx context.Context, key string, r io.Reader, mimeType string, size int64) (StoredObject, error) {
	uploader := manager.NewUploader(s.client)
	_, err := uploader.Upload(ctx, &s3.PutObjectInput{
		Bucket:        aws.String(s.bucket),
		Key:           aws.String(key),
		Body:          r,
		ContentType:   aws.String(mimeType),
		ContentLength: aws.Int64(size),
	})
	if err != nil {
		return StoredObject{}, fmt.Errorf("s3 upload: %w", err)
	}
	encodedKey := url.PathEscape(key)
	return StoredObject{Key: key, PublicURL: fmt.Sprintf("%s/%s", s.publicBase, encodedKey)}, nil
}

func (s *s3Storage) Delete(ctx context.Context, key string) error {
	_, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return fmt.Errorf("s3 delete: %w", err)
	}
	return nil
}

type noopStorage struct{}

func (n *noopStorage) Upload(_ context.Context, _ string, _ io.Reader, _ string, _ int64) (StoredObject, error) {
	return StoredObject{}, fmt.Errorf("storage not configured: set S3_BUCKET and related env vars")
}

func (n *noopStorage) Delete(_ context.Context, _ string) error {
	return nil
}
