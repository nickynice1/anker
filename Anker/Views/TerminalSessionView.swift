import SwiftUI

/// Eine Tab-Seite: Kopfzeile mit Status, darunter das Terminal selbst. Tippt
/// man das Terminal an, geht die Tastatur auf und jedes Zeichen geht direkt
/// an die SSH-Sitzung — genau wie bei einem echten Terminal, Enter sendet die
/// Zeile ganz normal ab. Keine Autokorrektur hier (SwiftTerm nutzt `UIKeyInput`,
/// nicht das volle `UITextInput`, das iOS für Vorschläge braucht), dafür
/// funktionieren vim, Pfeiltasten in tmux und Ähnliches sofort richtig.
struct TerminalSessionView: View {
    let verbindung: SSHConnection
    /// Ob das hier gerade der sichtbare Tab ist. Diese Ansicht bleibt auch
    /// für Tabs im Hintergrund aufgebaut (siehe `TerminalTabsView`), braucht
    /// also eine eigene Information darüber, statt sich allein auf „ich
    /// existiere" zu verlassen.
    let istAktiv: Bool
    @Environment(\.scenePhase) private var szenenPhase

    /// Direkt von `verbindung.beobachtbar` gelesen, nicht mehr über einen
    /// `AsyncStream` beobachtet -- der wurde vorher GLEICHZEITIG von dieser
    /// Ansicht UND der Tab-Kachel konsumiert, ein `AsyncStream` liefert aber
    /// jedes Element an nur EINEN wartenden Leser. Die beiden sahen darum nie
    /// denselben Zustand. `@Observable` benachrichtigt dagegen jeden Leser.
    private var zustand: ConnectionState { verbindung.beobachtbar.wert }

    var body: some View {
        VStack(spacing: 0) {
            kopfzeile
            TerminalViewRepresentable(verbindung: verbindung, istAktiv: istAktiv)
                .background(Theme.terminalBackground)
        }
        .background(Theme.terminalBackground)
        .task {
            // Verbindet wird NICHT hier primär ausgelöst, sondern von der
            // allerersten echten Größenmeldung aus `TerminalViewRepresentable`
            // -- sonst würde mit einem Schätzwert statt der echten
            // Bildschirmbreite verbunden (siehe dort). Diese Zeit misst
            // SwiftTerm selbst, nicht die Uhr: Falls sie aus irgendeinem
            // Grund ausbleibt, verbindet dieses Sicherheitsnetz trotzdem noch,
            // einmalig -- `verbinden()` ist gegen Mehrfachaufrufe abgesichert.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await verbindung.verbinden()
        }
        .onChange(of: szenenPhase) { _, neuePhase in
            // iOS pausiert die Verbindung ohnehin nach kurzer Zeit im
            // Hintergrund — hier geht nichts verloren, weil die eigentliche
            // Sitzung per tmux auf dem Server weiterläuft. Beim Zurückkommen
            // wird einfach neu verbunden und automatisch wieder angehängt.
            // Das ist ein bewusster, von einer menschlichen Handlung
            // (App wieder in den Vordergrund holen) ausgelöster Versuch --
            // anders als die automatische Erstverbindung bei einer
            // Größenänderung wird hier absichtlich IMMER neu versucht, auch
            // nach einem vorherigen Fehlschlag.
            if neuePhase == .active, case .fehlgeschlagen = zustand {
                Task { await verbindung.erneutVerbinden() }
            } else if neuePhase == .active, case .getrennt = zustand {
                Task { await verbindung.erneutVerbinden() }
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
            // Erscheint nur, wenn es etwas zu tun gibt: Nach einem Fehlschlag
            // oder einem beendeten Shell-Ende verbindet NICHTS mehr von
            // selbst (siehe `SSHConnection.jeVersucht`) -- absichtlich, damit
            // ein falsches Passwort nicht in einer Serie automatischer
            // Versuche endet. Dafür braucht es diesen Knopf. Das zusätzliche
            // `jeVersucht` verhindert, dass er im allerersten Moment eines
            // neu geöffneten Tabs aufblitzt, bevor der erste Versuch überhaupt
            // begonnen hat -- auch dann ist der Zustand noch `.getrennt`.
            if verbindung.beobachtbar.jeVersucht {
                if case .fehlgeschlagen = zustand {
                    erneutVerbindenKnopf
                } else if case .getrennt = zustand {
                    erneutVerbindenKnopf
                }
            }
            Button {
                // Tmux-Standardkombination zum Trennen: erst die Präfixtaste
                // (Strg+B), danach „d" -- genau was man sonst von Hand tippen
                // würde, nur als ein Antippen. Läuft außerhalb von tmux in die
                // Shell oder ein anderes Programm statt ins Leere.
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

    private var erneutVerbindenKnopf: some View {
        Button {
            Task { await verbindung.erneutVerbinden() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .accessibilityLabel("Erneut verbinden")
    }
}
