import SwiftUI
import SwiftTerm

/// Bindet SwiftTerms echte `TerminalView` (UIKit) in SwiftUI ein — bewusst
/// selbst geschrieben statt SwiftTerms eigene `SwiftUITerminalView` zu
/// nehmen: die ist im Quelltext ausdrücklich als "Internal, for testing"
/// markiert und nur in Debug-Builds überhaupt enthalten.
///
/// Wichtig zum Verständnis der App: Diese Ansicht ist nur für die AUSGABE
/// und für den Rohmodus (direkte Tastatur, kein Autokorrektur-möglich — dazu
/// unten mehr). Die normale Eingabe läuft über ein eigenes Textfeld in
/// `TerminalSessionView`.
struct TerminalViewRepresentable: UIViewRepresentable {
    let verbindung: SSHConnection
    @Binding var rohModus: Bool
    /// Erhöht sich bei jedem Tab-Wechsel um den rohen Eingabefokus zu setzen.
    var fokusAnfrage: Int

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let ansicht = SwiftTerm.TerminalView(frame: .zero)
        ansicht.terminalDelegate = context.coordinator
        ansicht.backgroundColor = UIColor(Theme.terminalBackground)
        // SwiftTerm nennt das UIKit-Eingabeprotokoll `UIKeyInput`, nicht das
        // volle `UITextInput` — deshalb zeigt iOS hier grundsätzlich keine
        // Autokorrektur-Vorschlagsleiste an, auch nicht im Rohmodus. Das ist
        // kein Fehlen einer Einstellung, sondern wie das Protokoll aufgebaut
        // ist. Genau deshalb gibt es das eigene Eingabefeld daneben.
        ansicht.autocorrectionType = .no
        ansicht.smartQuotesType = .no
        ansicht.smartDashesType = .no
        context.coordinator.verbindung = verbindung
        context.coordinator.ansicht = ansicht
        context.coordinator.anAusgabeHängen()
        return ansicht
    }

    func updateUIView(_ ansicht: SwiftTerm.TerminalView, context: Context) {
        if rohModus {
            ansicht.becomeFirstResponder()
        } else {
            ansicht.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Koordinator { Koordinator() }

    @MainActor
    final class Koordinator: NSObject, TerminalViewDelegate {
        var verbindung: SSHConnection?
        weak var ansicht: SwiftTerm.TerminalView?
        private var ausgabeAufgabe: Task<Void, Never>?

        /// Liest den Byte-Strom der Verbindung und füttert ihn laufend ins
        /// Terminal. Läuft so lange die Koordinator-Instanz lebt.
        func anAusgabeHängen() {
            guard let verbindung else { return }
            ausgabeAufgabe?.cancel()
            ausgabeAufgabe = Task { [weak self, verbindung] in
                for await stück in verbindung.ausgabe {
                    guard let ansicht = self?.ansicht else { return }
                    ansicht.feed(byteArray: stück[...])
                }
            }
        }

        deinit { ausgabeAufgabe?.cancel() }

        // MARK: TerminalViewDelegate

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            guard let verbindung else { return }
            Task { await verbindung.rohSenden(Array(data)) }
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard let verbindung else { return }
            Task { await verbindung.größeÄndern(spalten: newCols, zeilen: newRows) }
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
        func bell(source: SwiftTerm.TerminalView) {}
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
        }
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}
