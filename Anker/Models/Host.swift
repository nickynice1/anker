import Foundation

/// Wie sich ein Host anmeldet. Das Geheimnis selbst (Passwort oder privater
/// Schlüssel) steht NIE in dieser Struktur — nur ein Verweis auf den
/// Schlüsselbund-Eintrag. Siehe `KeychainStore`.
enum AuthArt: String, Codable, CaseIterable, Identifiable {
    case passwort
    case schluessel

    var id: String { rawValue }

    var beschriftung: String {
        switch self {
        case .passwort: "Passwort"
        case .schluessel: "SSH-Schlüssel"
        }
    }
}

/// Ein gespeicherter Server. Alles hier ist unkritisch und darf in einer
/// normalen Datei liegen — das Geheimnis liegt getrennt im Schlüsselbund,
/// adressiert über `id`.
struct Host: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var adresse: String
    var port: Int = 22
    var benutzer: String
    var authArt: AuthArt = .passwort
    /// Wird direkt nach dem Verbinden gesendet, z. B. `tmux attach -t main || tmux new -s main`.
    /// Leer heißt: keiner, man landet direkt in der normalen Shell.
    var startBefehl: String = ""
    /// Reihenfolge in der Liste, frei einstellbar.
    var reihenfolge: Int = 0

    static func leer() -> Host {
        Host(name: "", adresse: "", benutzer: "root")
    }

    /// Fertige Vorlage: Shell direkt in eine tmux-Sitzung attachen, neu
    /// anlegen falls noch keine läuft. Das ist der Normalfall, den Niklas
    /// wollte.
    static let tmuxStandardBefehl = "tmux attach -t main || tmux new -s main"
}
