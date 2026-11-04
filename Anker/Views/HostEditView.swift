import SwiftUI

/// Formular zum Anlegen oder Ändern eines Hosts. Das Geheimnis (Passwort
/// oder Schlüsseltext) wird separat gehalten und erst beim Speichern an den
/// Schlüsselbund übergeben — landet also nie zusammen mit den übrigen
/// Feldern in der Host-Datei.
struct HostEditView: View {
    @Bindable var hosts: HostsStore
    @State var host: Host

    @Environment(\.dismiss) private var schließen
    @State private var geheimnis = ""
    @State private var istNeu: Bool

    init(hosts: HostsStore, host: Host) {
        self.hosts = hosts
        self._host = State(initialValue: host)
        self._istNeu = State(initialValue: !hosts.hosts.contains { $0.id == host.id })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Name (z. B. earth)", text: $host.name)
                        .textInputAutocapitalization(.never)
                    TextField("Adresse oder IP", text: $host.adresse)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("22", value: $host.port, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                    TextField("Benutzer", text: $host.benutzer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Anmeldung") {
                    Picker("Art", selection: $host.authArt) {
                        ForEach(AuthArt.allCases) { art in
                            Text(art.beschriftung).tag(art)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch host.authArt {
                    case .passwort:
                        SecureField("Passwort", text: $geheimnis)
                    case .schluessel:
                        TextField("Privater Schlüssel (OpenSSH-Format)", text: $geheimnis, axis: .vertical)
                            .font(Theme.monoFont)
                            .lineLimit(3...8)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if !istNeu {
                        Text("Leer lassen, um das gespeicherte Geheimnis zu behalten.")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Section {
                    TextField("z. B. tmux attach -t main || tmux new -s main", text: $host.startBefehl, axis: .vertical)
                        .font(Theme.monoFont)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("tmux-Standard einsetzen") {
                        host.startBefehl = Host.tmuxStandardBefehl
                    }
                    .font(Theme.captionFont)
                } header: {
                    Text("Beim Verbinden ausführen")
                } footer: {
                    Text("Läuft automatisch direkt nach dem Login, bevor du etwas tippst. Leer lassen für eine normale Shell.")
                }

                if !istNeu {
                    Section {
                        Button("Server löschen", role: .destructive) {
                            hosts.entfernen(host)
                            schließen()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(istNeu ? "Neuer Server" : host.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { schließen() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { sichern() }
                        .disabled(host.name.isEmpty || host.adresse.isEmpty || host.benutzer.isEmpty)
                }
            }
        }
    }

    private func sichern() {
        if istNeu {
            hosts.hinzufügen(host, geheimnis: geheimnis)
        } else {
            hosts.aktualisieren(host, geheimnis: geheimnis.isEmpty ? nil : geheimnis)
        }
        schließen()
    }
}
