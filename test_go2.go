package main

import (
	"fmt"
	"github.com/reearth/ygo/sync"
	"github.com/reearth/ygo/crdt"
	"bytes"
)

func main() {
	payload := []byte{0, 0} // A valid empty update [numClients=0, deleteSet=0]
	
	msg := []byte{2, byte(len(payload))} 
	msg = append(msg, payload...)
	
	originalMsg := make([]byte, len(msg))
	copy(originalMsg, msg)
	
	_, decodedPayload, _ := sync.ReadSyncMessage(msg)
	
	doc := crdt.NewDoc()
	sync.ApplySyncMessage(doc, msg, "remote")
	
	if !bytes.Equal(msg, originalMsg) {
		fmt.Printf("msg WAS MODIFIED! %v\n", msg)
	}
	
	encoded := sync.EncodeUpdate(decodedPayload)
	fmt.Printf("Encoded length=%v\n", len(encoded))
}
