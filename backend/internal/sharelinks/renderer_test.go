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

func TestRenderDocumentGroupsConsecutiveListsAndIncludesFirstItemInPlainText(t *testing.T) {
	page, err := RenderDocument([]byte(`{"schemaVersion":1,"blocks":[
		{"id":"one","type":"bulletList","delta":[{"insert":"One"}],"metadata":{}},
		{"id":"two","type":"bulletList","delta":[{"insert":"Two"}],"metadata":{}},
		{"id":"three","type":"orderedList","delta":[{"insert":"Three"}],"metadata":{}}
	]}`), RenderOptions{})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if strings.Count(page.HTML, "<ul>") != 1 || strings.Count(page.HTML, "</ul>") != 1 {
		t.Fatalf("bullet list was fragmented: %s", page.HTML)
	}
	if strings.Count(page.HTML, "<ol>") != 1 || strings.Count(page.HTML, "</ol>") != 1 {
		t.Fatalf("ordered list was fragmented: %s", page.HTML)
	}
	for _, item := range []string{"One", "Two", "Three"} {
		if !strings.Contains(page.Text, item) {
			t.Fatalf("plain text omitted %q: %q", item, page.Text)
		}
	}
}

func TestRenderDocumentOnlyLinksSafeHTTPURLs(t *testing.T) {
	page, err := RenderDocument([]byte(`{"schemaVersion":1,"blocks":[
		{"id":"safe","type":"paragraph","delta":[{"insert":"safe","attributes":{"link":"https://example.com"}}],"metadata":{}},
		{"id":"unsafe","type":"paragraph","delta":[{"insert":"unsafe","attributes":{"link":"javascript:alert(1)"}}],"metadata":{}},
		{"id":"internal","type":"paragraph","delta":[{"insert":"internal","attributes":{"link":"note://private"}}],"metadata":{}}
	]}`), RenderOptions{})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	if !strings.Contains(page.HTML, `href="https://example.com"`) {
		t.Fatalf("safe link was not rendered: %s", page.HTML)
	}
	if strings.Contains(page.HTML, "javascript:") || strings.Contains(page.HTML, `href="note://`) {
		t.Fatalf("unsafe or internal link became actionable: %s", page.HTML)
	}
}

func TestRenderDocumentRejectsInvalidCanonicalSnapshots(t *testing.T) {
	for _, snapshot := range []string{
		`{}`,
		`{"schemaVersion":2,"blocks":[]}`,
		`{"schemaVersion":1,"blocks":[]}`,
		`{"schemaVersion":1,"blocks":[{"id":"same","type":"paragraph","delta":[],"metadata":{}},{"id":"same","type":"paragraph","delta":[],"metadata":{}}]}`,
	} {
		if _, err := RenderDocument([]byte(snapshot), RenderOptions{}); err == nil {
			t.Fatalf("snapshot was accepted: %s", snapshot)
		}
	}
}

func TestRenderDocumentIncludesSafeRichLinkMetadata(t *testing.T) {
	page, err := RenderDocument([]byte(`{"schemaVersion":1,"blocks":[
		{"id":"link","type":"rich_link","delta":[],"metadata":{"url":"https://example.com","title":"Example","description":"A safe link"}}
	]}`), RenderOptions{})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	for _, fragment := range []string{`class="rich-link"`, `href="https://example.com"`, "Example", "A safe link"} {
		if !strings.Contains(page.HTML, fragment) {
			t.Fatalf("rich link omitted %q: %s", fragment, page.HTML)
		}
	}
}
