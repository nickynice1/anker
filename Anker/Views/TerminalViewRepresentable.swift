import SwiftUI
import SwiftTerm

/// Bindet SwiftTerms echte `TerminalView` (UIKit) in SwiftUI ein — bewusst
/// selbst geschrieben statt SwiftTerms eigene `SwiftUITerminalView` zu
/// nehmen: die ist im Quelltext ausdrücklich als "Internal, for testing"
/// markiert und nur in Debug-Builds überhaupt enthalten.
///
/// Das Terminal ist immer direkt bedienbar: Antippen holt die Tastatur,
/// jedes Zeichen geht sofort an die SSH-Sitzung. Autokorrektur kann iOS hier
/// grundsätzlich nicht anbieten — SwiftTerm nutzt das UIKit-Eingabeprotokoll
/// `UIKeyInput`, nicht das volle `UITextInput`, das iOS dafür braucht.
struct TerminalViewRepresentable: UIViewRepresentable {
    let verbindung: SSHConnection

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let ansicht = SwiftTerm.TerminalView(frame: .zero)
        ansicht.terminalDelegate = context.coordinator
        ansicht.backgroundColor = UIColor(Theme.terminalBackground)
        ansicht.autocorrectionType = .no
        ansicht.smartQuotesType = .no
        ansicht.smartDashesType = .no
        context.coordinator.verbindung = verbindung
        context.coordinator.ansicht = ansicht
        context.coordinator.anAusgabeHängen()
        return ansicht
    }

    func updateUIView(_ ansicht: SwiftTerm.TerminalView, context: Context) {
        // Läuft bei jeder SwiftUI-Aktualisierung erneut, u. a. direkt nach dem
        // Erzeugen und nach jedem Tab-Wechsel (TerminalSessionView trägt dort
        // ein `.id`, das die ganze Ansicht neu aufbaut) — dadurch bekommt das
        // Terminal beim Öffnen und beim Wechseln zuverlässig die Tastatur.
        if !ansicht.isFirstResponder {
            ansicht.becomeFirstResponder()
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
