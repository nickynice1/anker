import SwiftUI

/// Eine Tab-Seite: Kopfzeile mit Status, das Terminal selbst, darunter die
/// Befehlszeile mit normaler iOS-Autokorrektur. Der Rohmodus-Knopf schaltet
/// auf direkte Tastatureingabe ohne Autokorrektur um — für vim, Pfeiltasten
/// in tmux, Suchen mit `/` in `less` und Ähnliches, wo jedes Zeichen sofort
/// ankommen muss.
struct TerminalSessionView: View {
    let verbindung: SSHConnection
    @Environment(\.scenePhase) private var szenenPhase

    @State private var zustand: ConnectionState = .getrennt
    @State private var rohModus = false
    @State private var fokusAnfrage = 0
    @State private var eingabe = ""
    @FocusState private var befehlszeileFokussiert: Bool

    var body: some View {
        VStack(spacing: 0) {
            kopfzeile
            TerminalViewRepresentable(
                verbindung: verbindung,
                rohModus: $rohModus,
                fokusAnfrage: fokusAnfrage
            )
            .background(Theme.terminalBackground)

            if !rohModus {
                befehlszeile
            }
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
                rohModus.toggle()
                fokusAnfrage += 1
                if !rohModus { befehlszeileFokussiert = true }
            } label: {
                Label(rohModus ? "Normal" : "Direkt", systemImage: rohModus ? "keyboard" : "keyboard.badge.ellipsis")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(rohModus ? Theme.accent : Theme.textSecondary)
            }
            .accessibilityLabel(rohModus ? "Zur normalen Eingabe mit Autokorrektur wechseln" : "Zur direkten Tastatureingabe wechseln")
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }

    private var befehlszeile: some View {
        HStack(spacing: 10) {
            TextField("Befehl …", text: $eingabe, axis: .vertical)
                .font(Theme.monoFont)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled(false)
                .textInputAutocapitalization(.never)
                .lineLimit(1...4)
                .focused($befehlszeileFokussiert)
                .onSubmit { absenden() }
                .submitLabel(.send)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))

            Button {
                absenden()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(eingabe.isEmpty ? Theme.textSecondary : Theme.accent)
            }
            .disabled(eingabe.isEmpty)
        }
        .padding(.horizontal, Theme.cardPadding)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }

    private func absenden() {
        guard !eingabe.isEmpty else { return }
        let text = eingabe
        eingabe = ""
        Task { await verbindung.zeileSenden(text) }
    }
}
