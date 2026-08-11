package sharelinks

import (
	"bytes"
	"fmt"
	"html"
	"net/url"
	"strings"

	"github.com/fmpwizard/go-quilljs-delta/delta"

	"github.com/RigleyC/supanotes/internal/noteoperations"
)

const fallbackTitle = "Nota compartilhada no SupaNotes"

type RenderedPage struct {
	Title string
	HTML  string
	Text  string
}

type RenderOptions struct {
	AttachmentBaseURL string
}

func RenderDocument(data []byte, options RenderOptions) (RenderedPage, error) {
	doc, err := noteoperations.DecodeCanonicalDocument(data)
	if err != nil {
		return RenderedPage{}, fmt.Errorf("decode document: %w", err)
	}
	return renderDocument(doc, options), nil
}

func renderDocument(doc noteoperations.Document, options RenderOptions) RenderedPage {
	base := strings.TrimRight(options.AttachmentBaseURL, "/")

	var body bytes.Buffer
	var plain strings.Builder
	title := documentTitle(doc)
	for index := 0; index < len(doc.Blocks); {
		block := doc.Blocks[index]
		text := blockText(block.Delta)
		if listType := noteoperations.BlockType(block.Type); listType == noteoperations.BlockBulletList || listType == noteoperations.BlockOrderedList {
			end := index
			for end < len(doc.Blocks) && noteoperations.BlockType(doc.Blocks[end].Type) == listType {
				end++
			}
			body.WriteString(renderList(doc.Blocks[index:end], listType))
			for _, listBlock := range doc.Blocks[index:end] {
				listText := blockText(listBlock.Delta)
				if strings.TrimSpace(listText) != "" {
					plain.WriteString(listText)
					plain.WriteString("\n")
				}
			}
			index = end
			continue
		}
		body.WriteString(renderBlock(block, base))
		if strings.TrimSpace(text) != "" {
			plain.WriteString(text)
			plain.WriteString("\n")
		}
		index++
	}
	if title == "" {
		title = fallbackTitle
	}
	return RenderedPage{Title: title, HTML: body.String(), Text: strings.TrimSpace(plain.String())}
}

func documentTitle(doc noteoperations.Document) string {
	for _, block := range doc.Blocks {
		if text := strings.TrimSpace(blockText(block.Delta)); text != "" {
			return text
		}
	}
	return fallbackTitle
}

func renderList(blocks []noteoperations.Block, blockType noteoperations.BlockType) string {
	tag := "ul"
	if blockType == noteoperations.BlockOrderedList {
		tag = "ol"
	}
	var body strings.Builder
	for _, block := range blocks {
		body.WriteString("<li>")
		body.WriteString(renderInline(block.Delta))
		body.WriteString("</li>")
	}
	return "<" + tag + ">" + body.String() + "</" + tag + ">"
}

func renderBlock(block noteoperations.Block, attachmentBaseURL string) string {
	content := renderInline(block.Delta)
	switch noteoperations.BlockType(block.Type) {
	case noteoperations.BlockHeader1:
		return "<h1>" + content + "</h1>"
	case noteoperations.BlockHeader2:
		return "<h2>" + content + "</h2>"
	case noteoperations.BlockHeader3:
		return "<h3>" + content + "</h3>"
	case noteoperations.BlockQuote:
		return "<blockquote>" + content + "</blockquote>"
	case noteoperations.BlockBulletList, noteoperations.BlockOrderedList:
		return "<p>" + content + "</p>"
	case noteoperations.BlockTask:
		checked := false
		if value, ok := block.Metadata["isCompleted"].(bool); ok {
			checked = value
		}
		if value, ok := block.Metadata["checked"].(bool); ok {
			checked = value
		}
		checkedAttr := ""
		if checked {
			checkedAttr = " checked"
		}
		return `<p class="task"><input type="checkbox" disabled` + checkedAttr + `> <span>` + content + "</span></p>"
	case noteoperations.BlockDivider:
		return "<hr>"
	case noteoperations.BlockAttachment:
		attachmentID, _ := block.Metadata["attachmentId"].(string)
		if attachmentID == "" {
			attachmentID, _ = block.Metadata["attachment_id"].(string)
		}
		if attachmentID == "" || attachmentBaseURL == "" {
			return "<p>Attachment</p>"
		}
		return `<p><a href="` + html.EscapeString(attachmentBaseURL+"/"+url.PathEscape(attachmentID)) + `">Attachment</a></p>`
	case noteoperations.BlockRichLink:
		richURL, _ := block.Metadata["url"].(string)
		richTitle, _ := block.Metadata["title"].(string)
		richDescription, _ := block.Metadata["description"].(string)
		if !safeWebURL(richURL) {
			return "<p>" + content + "</p>"
		}
		if strings.TrimSpace(richTitle) == "" {
			richTitle = richURL
		}
		result := `<article class="rich-link"><a href="` + html.EscapeString(richURL) + `" target="_blank" rel="noopener noreferrer"><strong>` + html.EscapeString(richTitle) + `</strong>`
		if strings.TrimSpace(richDescription) != "" {
			result += `<br><span>` + html.EscapeString(richDescription) + `</span>`
		}
		return result + "</a></article>"
	default:
		if strings.TrimSpace(stripTags(content)) == "" {
			return ""
		}
		return "<p>" + content + "</p>"
	}
}

func renderInline(ops []delta.Op) string {
	var out strings.Builder
	for _, op := range ops {
		if len(op.Insert) == 0 {
			continue
		}
		text := html.EscapeString(string(op.Insert))
		if link, ok := op.Attributes["link"].(string); ok && safeWebURL(link) {
			text = `<a href="` + html.EscapeString(link) + `" target="_blank" rel="noopener noreferrer">` + text + "</a>"
		}
		if bold, ok := op.Attributes["bold"].(bool); ok && bold {
			text = "<strong>" + text + "</strong>"
		}
		if italic, ok := op.Attributes["italic"].(bool); ok && italic {
			text = "<em>" + text + "</em>"
		}
		out.WriteString(text)
	}
	return strings.ReplaceAll(out.String(), "\n", "<br>")
}

func blockText(ops []delta.Op) string {
	var b strings.Builder
	for _, op := range ops {
		if len(op.Insert) > 0 {
			b.WriteString(string(op.Insert))
		}
	}
	return b.String()
}

func safeWebURL(raw string) bool {
	parsed, err := url.Parse(raw)
	if err != nil {
		return false
	}
	return parsed.Scheme == "http" || parsed.Scheme == "https"
}

func stripTags(value string) string {
	var out bytes.Buffer
	inTag := false
	for _, r := range value {
		switch r {
		case '<':
			inTag = true
		case '>':
			inTag = false
		default:
			if !inTag {
				out.WriteRune(r)
			}
		}
	}
	return out.String()
}
