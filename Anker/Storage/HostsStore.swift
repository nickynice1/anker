import Foundation
import Observation

/// Hält die Host-Liste im Speicher und auf der Platte (als JSON, ohne
/// Geheimnisse) und reicht Passwort/Schlüssel getrennt an den Schlüsselbund
/// weiter. `@Observable` statt `ObservableObject`, damit SwiftUI nur die
/// Ansichten neu zeichnet, die wirklich ein geändertes Feld lesen.
@Observable
final class HostsStore {
    private(set) var hosts: [Host] = []

    private let dateiPfad: URL = {
        let ordner = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        return ordner.appendingPathComponent("hosts.json")
    }()

    init() {
        laden()
        if hosts.isEmpty {
            hosts = Self.vorbelegung()
            speichern()
        }
    }

    // MARK: Lesen/Schreiben

    private func laden() {
        guard let daten = try? Data(contentsOf: dateiPfad) else { return }
        hosts = (try? JSONDecoder().decode([Host].self, from: daten)) ?? []
    }

    private func speichern() {
        guard let daten = try? JSONEncoder().encode(hosts) else { return }
        try? daten.write(to: dateiPfad, options: .atomic)
    }

    // MARK: Pflegen

    func hinzufügen(_ host: Host, geheimnis: String) {
        var host = host
        host.reihenfolge = (hosts.map(\.reihenfolge).max() ?? -1) + 1
        hosts.append(host)
        speichern()
        try? KeychainStore.speichern(geheimnis, für: host.id.uuidString)
    }

    func aktualisieren(_ host: Host, geheimnis: String?) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index] = host
        speichern()
        if let geheimnis, !geheimnis.isEmpty {
            try? KeychainStore.speichern(geheimnis, für: host.id.uuidString)
        }
    }

    func entfernen(_ host: Host) {
        hosts.removeAll { $0.id == host.id }
        speichern()
        KeychainStore.löschen(host.id.uuidString)
    }

    func geheimnis(für host: Host) -> String {
        (try? KeychainStore.lesen(host.id.uuidString)) ?? nil ?? ""
    }

    func verschieben(von quellen: IndexSet, nach ziel: Int) {
        hosts.move(fromOffsets: quellen, toOffset: ziel)
        for (i, _) in hosts.enumerated() { hosts[i].reihenfolge = i }
        speichern()
    }

    /// Die zwei Server, die von Anfang an da sein sollen. Adresse/Benutzer
    /// stimmen, das Passwort trägst du einmal in der App selbst nach — es
    /// steht aus gutem Grund in keiner Quelldatei.
    private static func vorbelegung() -> [Host] {
        [
            Host(
                name: "earth",
                adresse: "145.239.232.109",
                benutzer: "root",
                authArt: .passwort,
                startBefehl: Host.tmuxStandardBefehl,
                reihenfolge: 0
            ),
            Host(
                name: "Nova",
                adresse: "51.83.66.212",
                benutzer: "root",
                authArt: .passwort,
                startBefehl: Host.tmuxStandardBefehl,
                reihenfolge: 1
            ),
        ]
    }
}
