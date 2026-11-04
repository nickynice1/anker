import SwiftUI

/// Die Leiste oben, eine Kachel je offener Verbindung, plus ein Knopf, um
/// einen weiteren Host zu öffnen. Darunter wechselt der sichtbare Bereich
/// zur ausgewählten Sitzung — alle anderen bleiben im Speicher und damit
/// verbunden, nicht neu aufgebaut.
struct TerminalTabsView: View {
    @Bindable var sitzungen: SessionsManager
    @Bindable var hosts: HostsStore
    @State private var hostListeZeigen = false
    @State private var bearbeiteterHost: Host?

    var body: some View {
        VStack(spacing: 0) {
            tabLeiste

            if let aktiv = sitzungen.ausgewählt {
                TerminalSessionView(verbindung: aktiv)
                    .id(aktiv.host.id)
            } else {
                startseite
            }
        }
        .background(Theme.terminalBackground)
        .sheet(isPresented: $hostListeZeigen) {
            HostListView(hosts: hosts) { host in
                sitzungen.öffnen(host, geheimnis: hosts.geheimnis(für: host))
                hostListeZeigen = false
            }
        }
        .sheet(item: $bearbeiteterHost) { host in
            HostEditView(hosts: hosts, host: host)
        }
    }

    private var tabLeiste: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sitzungen.offeneVerbindungen, id: \.host.id) { verbindung in
                    TabKachel(
                        verbindung: verbindung,
                        istAktiv: sitzungen.ausgewählteID == verbindung.host.id
                    ) {
                        sitzungen.ausgewählteID = verbindung.host.id
                    } schließen: {
                        sitzungen.schließen(verbindung)
                    }
                }

                Button { hostListeZeigen = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 34)
                        .background(Theme.surfaceRaised, in: Circle())
                }
            }
            .padding(.horizontal, Theme.cardPadding)
            .padding(.vertical, 8)
        }
        .background(Theme.surface)
    }

    /// Die Startseite: alle gespeicherten Server auf einen Blick, unabhängig
    /// davon ob schon ein Tab dafür offen ist. Antippen öffnet ihn direkt —
    /// kein Umweg mehr über einen eigenen Knopf oder ein Sheet.
    private var startseite: some View {
        Group {
            if hosts.hosts.isEmpty {
                leerAnsicht
            } else {
                List {
                    ForEach(hosts.hosts.sorted(by: { $0.reihenfolge < $1.reihenfolge })) { host in
                        HostZeile(host: host) {
                            sitzungen.öffnen(host, geheimnis: hosts.geheimnis(für: host))
                        } bearbeiten: {
                            bearbeiteterHost = host
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.terminalBackground)
    }

    private var leerAnsicht: some View {
        VStack(spacing: Theme.spacing) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textSecondary)
            Text("Noch kein Server angelegt")
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textPrimary)
            Button("Server anlegen") { hostListeZeigen = true }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TabKachel: View {
    let verbindung: SSHConnection
    let istAktiv: Bool
    let auswählen: () -> Void
    let schließen: () -> Void
    @State private var zustand: ConnectionState = .getrennt

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(zustand.farbe).frame(width: 7, height: 7)
            Text(verbindung.host.name)
                .font(Theme.bodyFont.weight(istAktiv ? .semibold : .regular))
                .lineLimit(1)
            Button(action: schließen) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .foregroundStyle(istAktiv ? Theme.textPrimary : Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(istAktiv ? Theme.surfaceRaised : Color.clear)
        )
        .onTapGesture(perform: auswählen)
        .task {
            for await neuerZustand in verbindung.zustandsStrom {
                zustand = neuerZustand
            }
        }
    }
}
