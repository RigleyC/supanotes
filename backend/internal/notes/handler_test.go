package notes

import "testing"

func TestMapToNoteResponseIncludesShareMetadata(t *testing.T) {
	response := mapToNoteResponse(NoteResponseFields{
		Permission:    "view",
		SharedByEmail: "owner@example.com",
		SharedByName:  "Owner",
	})

	if response.Permission != "view" {
		t.Fatalf("permission = %q, want %q", response.Permission, "view")
	}
	if response.SharedByEmail != "owner@example.com" {
		t.Fatalf("shared_by_email = %q, want %q", response.SharedByEmail, "owner@example.com")
	}
	if response.SharedByName != "Owner" {
		t.Fatalf("shared_by_name = %q, want %q", response.SharedByName, "Owner")
	}
}
