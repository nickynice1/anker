import SwiftUI

/// Alle Farben und Schriften der App an einer Stelle, damit nirgendwo eine
/// Literal-Farbe im Code auftaucht. Jede Farbe ist für hell und dunkel
/// getrennt definiert, nicht nur invertiert.
enum Theme {
    // MARK: Farben

    static let accent = Color("AccentAnker")
    static let background = Color("Background")
    static let surface = Color("Surface")
    static let surfaceRaised = Color("SurfaceRaised")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let success = Color("StatusOnline")
    static let warning = Color("StatusConnecting")
    static let danger = Color("StatusOffline")
    static let terminalBackground = Color("TerminalBackground")

    // MARK: Typografie

    static let titleFont = Font.system(.title2, design: .rounded).weight(.semibold)
    static let headlineFont = Font.system(.headline, design: .rounded)
    static let bodyFont = Font.system(.body, design: .default)
    static let monoFont = Font.system(.body, design: .monospaced)
    static let captionFont = Font.system(.caption, design: .default)

    // MARK: Maße

    static let cornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let spacing: CGFloat = 12
}

/// Status einer Verbindung, mit eigener Farbe und eigenem Symbol — wird an
/// mehreren Stellen gebraucht (Host-Liste, Tab-Leiste, Terminal-Kopfzeile).
enum ConnectionState: Equatable {
    case getrennt
    case verbindet
    case verbunden
    case fehlgeschlagen(String)

    var farbe: Color {
        switch self {
        case .getrennt: Theme.textSecondary
        case .verbindet: Theme.warning
        case .verbunden: Theme.success
        case .fehlgeschlagen: Theme.danger
        }
    }

    var beschriftung: String {
        switch self {
        case .getrennt: "Getrennt"
        case .verbindet: "Verbindet…"
        case .verbunden: "Verbunden"
        case .fehlgeschlagen(let grund): grund
        }
    }
}
