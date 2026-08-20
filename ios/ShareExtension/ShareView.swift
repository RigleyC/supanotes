import SwiftUI

struct ShareView: View {
  let notes: [SharedShareNote]
  let onSelect: (SharedShareNote) -> Void

  @State private var query = ""

  var body: some View {
    NavigationView {
      List {
        TextField("Buscar nota", text: $query)
        ForEach(notes.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }, id: \.noteId) { note in
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
      .navigationTitle("Salvar link em")
    }
  }
}
