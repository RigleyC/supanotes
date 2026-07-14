package main

import (
	"fmt"
	"github.com/reearth/ygo/sync"
)

func main() {
	// Simulate Flutter sending [2, len, payload...]
	// Let's make a dummy payload of 3160 bytes
	payload := make([]byte, 3160)
	
	// Create the Flutter message
	msg := []byte{2, 216, 24} // 2, varUint(3160)
	msg = append(msg, payload...)
	
	msgType, decodedPayload, err := sync.ReadSyncMessage(msg)
	fmt.Printf("ReadSyncMessage returned: type=%v, err=%v, decodedPayloadLen=%v\n", msgType, err, len(decodedPayload))
	
	if err == nil {
		encoded := sync.EncodeUpdate(decodedPayload)
		fmt.Printf("Encoded length=%v\n", len(encoded))
		
		// What is in encoded?
		if len(encoded) >= 3 {
			fmt.Printf("Encoded prefix: %v\n", encoded[:3])
		}
	}
}
