import SwiftUI

struct ShareView: View {
  let notes: [SharedShareNote]
  let onCancel: () -> Void
  let onSelect: (SharedShareNote) -> Void

  @State private var query = ""

  var body: some View {
    NavigationView {
      Group {
        if notes.isEmpty {
          Text("Nenhuma nota editável encontrada.")
            .foregroundColor(.secondary)
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
  }

  private var list: some View {
    List {
      TextField("Buscar nota", text: $query)
      ForEach(
        notes.filter {
          query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
        },
        id: \.noteId,
      ) { note in
        Button {
          onSelect(note)
        } label: {
          VStack(alignment: .leading) {
            Text(note.title.isEmpty ? "Sem título" : note.title)
            Text(note.preview).lineLimit(2).font(.caption).foregroundColor(.secondary)
          }
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
    }
  }
}
