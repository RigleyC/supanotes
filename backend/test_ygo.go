package main

import (
	"fmt"
	"log"

	"github.com/reearth/ygo/crdt"
)

func main() {
	// Create client 1
	doc1 := crdt.New()
	m1 := doc1.GetMap("nodes")
	doc1.Transact(func(txn *crdt.Transaction) {
		m1.Set(txn, "n1", "hello")
	})
	state1 := crdt.EncodeStateAsUpdateV1(doc1, nil)

	// Create client 2 and apply WITHOUT pre-registering
	doc2 := crdt.New()
	err := crdt.ApplyUpdateV1(doc2, state1, nil)
	if err != nil {
		log.Fatal(err)
	}

	m2 := doc2.GetMap("nodes")
	fmt.Printf("Without pre-register: keys=%d\n", len(m2.Keys()))

	// Create client 3 and apply WITH pre-registering
	doc3 := crdt.New()
	doc3.GetMap("nodes") // pre-register
	err = crdt.ApplyUpdateV1(doc3, state1, nil)
	if err != nil {
		log.Fatal(err)
	}

	m3 := doc3.GetMap("nodes")
	fmt.Printf("With pre-register: keys=%d\n", len(m3.Keys()))
}
