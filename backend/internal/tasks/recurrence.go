package tasks

import (
	"crypto/sha256"
	"fmt"

	"github.com/google/uuid"
)

func GenerateDeterministicTaskID(templateID string, dueDate string) uuid.UUID {
	hash := sha256.Sum256([]byte(fmt.Sprintf("%s:%s", templateID, dueDate)))
	return uuid.Must(uuid.FromBytes(hash[:16]))
}
