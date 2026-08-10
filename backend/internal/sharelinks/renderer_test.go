package sharelinks

import (
	"strings"
	"testing"
)

func TestRenderDocumentEscapesTextAndDerivesTitle(t *testing.T) {
	page, err := RenderDocument([]byte(`{
      "schemaVersion":1,
      "blocks":[
        {"id":"h1","type":"header1","delta":[{"insert":"Welcome <script>"}],"metadata":{}},
        {"id":"task","type":"task","delta":[{"insert":"Read this"}],"metadata":{"isCompleted":true}},
        {"id":"divider","type":"divider","delta":[],"metadata":{}}
      ]
	}`), RenderOptions{})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if page.Title != "Welcome <script>" {
		t.Fatalf("title: got %q", page.Title)
	}
	if strings.Contains(page.HTML, "<script>") {
		t.Fatal("rendered HTML contains executable script markup")
	}
	if !strings.Contains(page.HTML, "Welcome &lt;script&gt;") {
		t.Fatal("rendered HTML did not escape text")
	}
	if !strings.Contains(page.HTML, `type="checkbox" disabled checked`) {
		t.Fatal("completed task is not a disabled checked checkbox")
	}
}

func TestRenderDocumentUsesFallbackTitle(t *testing.T) {
	page, err := RenderDocument([]byte(`{"schemaVersion":1,"blocks":[{"id":"p","type":"paragraph","delta":[],"metadata":{}}]}`), RenderOptions{})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if page.Title != "Nota compartilhada no SupaNotes" {
		t.Fatalf("title: got %q", page.Title)
	}
}
