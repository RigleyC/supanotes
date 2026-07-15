package main

import (
	"fmt"
	"testing"

	"github.com/reearth/ygo/crdt"
)

func TestEmptyUpdate(t *testing.T) {
	doc := crdt.New()
	update := crdt.EncodeStateAsUpdateV1(doc, nil)
	fmt.Printf("empty update v1: %v (%d bytes)\n", update, len(update))

	sv := doc.StateVector()
	diff := crdt.EncodeStateAsUpdateV1(doc, sv)
	fmt.Printf("diff with full sv: %v (%d bytes)\n", diff, len(diff))
}
