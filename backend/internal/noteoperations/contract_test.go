package noteoperations

import "testing"

func TestDocumentServiceContract_isImplementedByService(t *testing.T) {
	var service DocumentService = NewService(nil, nil)
	if service == nil {
		t.Fatal("expected document service implementation")
	}
}
