package main

import (
	"fmt"
	"github.com/reearth/ygo/crdt"
)

func main() {
	doc := crdt.New()
	svBytes := crdt.EncodeStateVectorV1(doc)
	fmt.Printf("State vector length: %d\n", len(svBytes))
	fmt.Printf("State vector: %v\n", svBytes)
	
	sv, _ := crdt.DecodeStateVectorV1(svBytes)
	update := crdt.EncodeStateAsUpdateV1(doc, sv)
	fmt.Printf("Update length: %d\n", len(update))
	fmt.Printf("Update: %v\n", update)
}
