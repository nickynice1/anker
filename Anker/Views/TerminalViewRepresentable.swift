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
        // SwiftTerm setzt die Textfarbe sonst auf `UIColor.label` -- das dreht
        // sich bei hellem Systemdesign ins fast Schwarze. Unser Terminal bleibt
        // aber bewusst in JEDER Systemeinstellung dunkel (siehe oben), darum
        // müssen Vordergrund und Hintergrund hier fest zusammenpassen, nicht
        // dem System überlassen bleiben -- sonst wird der Text unsichtbar.
        ansicht.nativeBackgroundColor = UIColor(Theme.terminalBackground)
        ansicht.nativeForegroundColor = .white
        ansicht.autocorrectionType = .no
        ansicht.smartQuotesType = .no
        ansicht.smartDashesType = .no
        context.coordinator.verbindung = verbindung
        context.coordinator.ansicht = ansicht
        context.coordinator.anAusgabeHängen()
        // Nur EINMAL beim Erzeugen fokussieren -- nicht in `updateUIView`, das
        // würde ein Zuklappen der Tastatur (z. B. über SwiftTerms eigenen
        // Zubehör-Knopf) bei der nächsten SwiftUI-Aktualisierung sofort wieder
        // aufheben. Antippen des Terminals holt die Tastatur bei Bedarf selbst
        // zurück, das erledigt SwiftTerm schon selbst.
        DispatchQueue.main.async { ansicht.becomeFirstResponder() }
        return ansicht
    }

    func updateUIView(_ ansicht: SwiftTerm.TerminalView, context: Context) {}

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

        /// SwiftTerm meldet hier JEDE Größenänderung, auch die allererste --
        /// die kommt praktisch sofort nach dem Einfügen in die View-Hierarchie,
        /// oft bevor überhaupt eine Verbindung existiert. Genau dafür wird sie
        /// gebraucht: Mit der echten Spalten-/Zeilenzahl verbinden, statt mit
        /// einem Schätzwert zu starten und hinterher umzugrößern, wo sich
        /// schon gezeichneter Inhalt (tmux-Statuszeile, TUI-Ausgabe) nicht
        /// sauber neu aufbaut, sondern überlagert. Ob das hier ein Erstaufbau
        /// oder ein Umgrößern ist, entscheidet der echte Verbindungsstatus,
        /// nicht nur "ist das die erste Meldung dieser View" -- sonst würde
        /// ein Tab-Wechsel direkt nach einer Drehung ins Leere laufen.
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard let verbindung else { return }
            Task {
                if await verbindung.istAktiv {
                    await verbindung.größeÄndern(spalten: newCols, zeilen: newRows)
                } else {
                    await verbindung.verbinden(spalten: newCols, zeilen: newRows)
                }
            }
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
