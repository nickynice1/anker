import SwiftUI

/// Die gespeicherten Server als Liste. Antippen öffnet den Server in einem
/// neuen Tab (über `onÖffnen`), der Bearbeiten-Knopf führt zum Formular.
struct HostListView: View {
    @Bindable var hosts: HostsStore
    var onÖffnen: (Host) -> Void

    @Environment(\.dismiss) private var schließen
    @State private var bearbeiteterHost: Host?
    @State private var neuerHostAnlegen = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(hosts.hosts.sorted(by: { $0.reihenfolge < $1.reihenfolge })) { host in
                    HostZeile(host: host) {
                        onÖffnen(host)
                    } bearbeiten: {
                        bearbeiteterHost = host
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet { hosts.entfernen(hosts.hosts[index]) }
                }
                .onMove(perform: hosts.verschieben)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Server")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") { schließen() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { neuerHostAnlegen = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $bearbeiteterHost) { host in
                HostEditView(hosts: hosts, host: host)
            }
            .sheet(isPresented: $neuerHostAnlegen) {
                HostEditView(hosts: hosts, host: .leer())
            }
        }
    }
}

private struct HostZeile: View {
    let host: Host
    let öffnen: () -> Void
    let bearbeiten: () -> Void

    var body: some View {
        Button(action: öffnen) {
            HStack(spacing: Theme.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text(host.name.prefix(1).uppercased())
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(host.benutzer)@\(host.adresse)")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button(action: bearbeiten) {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
        .padding(.vertical, 4)
    }
}
