import SwiftUI

/// Eine Tab-Seite: Kopfzeile mit Status, darunter das Terminal selbst. Tippt
/// man das Terminal an, geht die Tastatur auf und jedes Zeichen geht direkt
/// an die SSH-Sitzung — genau wie bei einem echten Terminal, Enter sendet die
/// Zeile ganz normal ab. Keine Autokorrektur hier (SwiftTerm nutzt `UIKeyInput`,
/// nicht das volle `UITextInput`, das iOS für Vorschläge braucht), dafür
/// funktionieren vim, Pfeiltasten in tmux und Ähnliches sofort richtig.
struct TerminalSessionView: View {
    let verbindung: SSHConnection
    @Environment(\.scenePhase) private var szenenPhase

    @State private var zustand: ConnectionState = .getrennt

    var body: some View {
        VStack(spacing: 0) {
            kopfzeile
            TerminalViewRepresentable(verbindung: verbindung)
                .background(Theme.terminalBackground)
        }
        .background(Theme.terminalBackground)
        .task {
            await verbindung.verbinden()
            for await neuerZustand in verbindung.zustandsStrom {
                zustand = neuerZustand
            }
        }
        .onChange(of: szenenPhase) { _, neuePhase in
            // iOS pausiert die Verbindung ohnehin nach kurzer Zeit im
            // Hintergrund — hier geht nichts verloren, weil die eigentliche
            // Sitzung per tmux auf dem Server weiterläuft. Beim Zurückkommen
            // wird einfach neu verbunden und automatisch wieder angehängt.
            if neuePhase == .active, case .fehlgeschlagen = zustand {
                Task { await verbindung.erneutVerbinden() }
            } else if neuePhase == .active, case .getrennt = zustand {
                Task { await verbindung.verbinden() }
            }
        }
    }

    private var kopfzeile: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(zustand.farbe)
                .frame(width: 8, height: 8)
            Text(verbindung.host.name)
                .font(Theme.headlineFont)
                .foregroundStyle(Theme.textPrimary)
            Text(zustand.beschriftung)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                // Tmux-Standardkombination zum Trennen: erst die Präfixtaste
                // (Strg+B), danach „d" -- genau was man sonst von Hand tippen
                // würde, nur als ein Antippen. Läuft auf einer Shell ohne tmux
                // einfach ins Leere, schadet also nicht.
                Task { await verbindung.rohSenden([0x02, UInt8(ascii: "d")]) }
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityLabel("Tmux-Sitzung trennen")
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }
}
