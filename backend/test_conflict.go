package main

import (
	"fmt"

	"github.com/reearth/ygo/crdt"
)

func main() {
	doc1 := crdt.New()
	map1 := doc1.GetMap("content/x")
	doc1.Transact(func(txn *crdt.Transaction) {
		map1.Set(txn, "foo", "bar")
	})
	state := crdt.EncodeStateAsUpdateV1(doc1, nil)

	doc2 := crdt.New()
	doc2.GetText("content/x") // Pre-register as YText
	
	err := crdt.ApplyUpdateV1(doc2, state, nil)
	if err != nil {
		fmt.Println("Apply error:", err)
		return
	}
	
	t := doc2.GetText("content/x")
	if t == nil {
		fmt.Println("It is NOT a YText!")
	} else {
		fmt.Println("It IS a YText!")
	}
}
