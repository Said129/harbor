import SwiftUI

struct MusicFilterTools: View {
    @Binding var filters: MusicFilters
    let count: Int
    var sources: [String] = ["local"]
    @AppStorage("harbor.music.playlistView") private var layout = "list"
    var body: some View {
        HStack(spacing: 12) {
            Text("\(count) canciones").font(.caption).foregroundStyle(.secondary)
            if filters.active { Button("Limpiar filtros") { filters.reset() }.font(.caption) }
            Spacer(minLength: 4)
            Menu {
                Section("Ordenar por") {
                    ForEach(MusicSort.allCases) { sort in
                        Button {
                            filters.descending = filters.sort == sort ? !filters.descending : false
                            filters.sort = sort
                        } label: {
                            if filters.sort == sort { Label(sort.title, image: "music-check") }
                            else { Text(sort.title) }
                        }
                    }
                    Toggle("Orden inverso", isOn: $filters.descending).disabled(filters.sort == .original)
                }
                Picker("Vista", selection: $layout) { Text("Lista").tag("list"); Text("Compacta").tag("compact") }
                if sources.count > 1 {
                    Picker("Fuente", selection: $filters.source) {
                        Text("Todas").tag("all")
                        ForEach(sources, id: \.self) { Text($0 == "local" ? "Archivos locales" : $0).tag($0) }
                    }
                }
                Picker("Contenido", selection: $filters.content) { ForEach(MusicContentFilter.allCases) { Text($0.title).tag($0) } }
            } label: {
                HStack(spacing: 5) {
                    Text(filters.sort.title).font(.caption).lineLimit(1)
                    if filters.descending && filters.sort != .original { Image("music-arrow-down").resizable().scaledToFit().frame(width: 12, height: 12).rotationEffect(.degrees(180)) }
                    Image("music-filter").resizable().scaledToFit().frame(width: 22, height: 22)
                }.frame(minHeight: 44)
            }.accessibilityLabel("Opciones de canciones").accessibilityValue(filters.sort.title)
        }
    }
}
