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
