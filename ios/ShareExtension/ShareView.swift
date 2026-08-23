import SwiftUI

struct ShareView: View {
  let notes: [SharedShareNote]
  let onCancel: () -> Void
  let onSelect: (SharedShareNote) -> Void

  @State private var query = ""
  @State private var selectedNoteId: String?

  var body: some View {
    NavigationView {
      Group {
        if notes.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "note.text")
              .font(.system(size: 40))
              .foregroundColor(.secondary)
            Text("Nenhuma nota encontrada.")
              .font(.headline)
              .foregroundColor(.secondary)
          }
          .padding()
        } else {
          list
        }
      }
      .navigationTitle("Salvar link em")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancelar") {
            onCancel()
          }
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  private var filteredNotes: [SharedShareNote] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return notes
    }
    return notes.filter { note in
      note.displayTitle.localizedCaseInsensitiveContains(trimmed) ||
      note.displayPreview.localizedCaseInsensitiveContains(trimmed)
    }
  }

  private var list: some View {
    List {
      Section {
        TextField("Buscar nota...", text: $query)
      }

      Section {
        ForEach(filteredNotes, id: \.noteId) { note in
          Button {
            selectedNoteId = note.noteId
            onSelect(note)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(note.displayTitle)
                  .font(.body)
                  .fontWeight(.medium)
                  .foregroundColor(.primary)
                if !note.displayPreview.isEmpty {
                  Text(note.displayPreview)
                    .lineLimit(2)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
              }
              Spacer()
              if selectedNoteId == note.noteId {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(.accentColor)
              }
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

/// Terminal states (no URL / queued for the app): message + close.
struct ShareResultView: View {
  let message: String
  let onDismiss: () -> Void

  var body: some View {
    NavigationView {
      VStack(spacing: 16) {
        Text(message)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
        Button("Concluir") { onDismiss() }
          .buttonStyle(.borderedProminent)
      }
      .navigationTitle("SupaNotes")
      .navigationBarTitleDisplayMode(.inline)
    }
    .navigationViewStyle(.stack)
  }
}
