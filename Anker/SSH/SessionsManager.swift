import Foundation
import Observation

/// Hält die gerade offenen Tabs auseinander von der gespeicherten Host-
/// Liste. Ein Host kann null, eine oder (theoretisch) mehrere offene
/// Verbindungen haben — in der Praxis meist eine.
@Observable
@MainActor
final class SessionsManager {
    private(set) var offeneVerbindungen: [SSHConnection] = []
    var ausgewählteID: UUID?

    func öffnen(_ host: Host, geheimnis: String) {
        if let bestehende = offeneVerbindungen.first(where: { $0.host.id == host.id }) {
            ausgewählteID = bestehende.host.id
            return
        }
        let verbindung = SSHConnection(host: host, geheimnisQuelle: { geheimnis })
        offeneVerbindungen.append(verbindung)
        ausgewählteID = host.id
    }

    func schließen(_ verbindung: SSHConnection) {
        Task { await verbindung.trennen() }
        offeneVerbindungen.removeAll { $0.host.id == verbindung.host.id }
        if ausgewählteID == verbindung.host.id {
            ausgewählteID = offeneVerbindungen.last?.host.id
        }
    }

    var ausgewählt: SSHConnection? {
        offeneVerbindungen.first { $0.host.id == ausgewählteID }
    }
}
