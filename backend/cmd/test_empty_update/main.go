package main

import (
	"fmt"

	"github.com/reearth/ygo/crdt"
)

func main() {
	doc := crdt.New()
	update := crdt.EncodeStateAsUpdateV1(doc, nil)
	fmt.Printf("empty update v1: %v (%d bytes)\n", update, len(update))

	state := crdt.EncodeStateAsUpdateV1(doc, nil)
	fmt.Printf("state v1: %v (%d bytes)\n", state, len(state))

	sv := doc.StateVector()
	diff := crdt.EncodeStateAsUpdateV1(doc, sv)
	fmt.Printf("diff with full sv: %v (%d bytes)\n", diff, len(diff))
}
