import Foundation
import Citadel
import NIO
import NIOSSH
import Crypto

/// Eine einzelne, langlebige Verbindung zu einem Host. Ein Actor, weil von
/// mehreren Stellen gleichzeitig geschrieben/gelesen wird (SwiftUI-Ansicht,
/// Hintergrund-Wiederverbindung) und hier nichts sich gegenseitig
/// überschreiben darf.
///
/// Wichtig, und bewusst so gebaut: Diese Klasse wirft NIE einen Fehler nach
/// außen, den SwiftUI nicht abfangen könnte — jeder Fehlschlag landet in
/// `zustand`, nichts lässt die App abstürzen. Siehe Anmerkung unten zu iOS
/// im Hintergrund.
actor SSHConnection {
    /// Unveränderlich nach dem Anlegen, deshalb bewusst `nonisolated` — sonst
    /// bräuchte selbst das Lesen des Host-Namens für eine Tab-Beschriftung
    /// ein `await`.
    nonisolated let host: Host

    private(set) var zustand: ConnectionState = .getrennt {
        didSet { zustandWeiterleiten.yield(zustand) }
    }
    private var schreiber: TTYStdinWriter?
    private var laufendeAufgabe: Task<Void, Never>?

    /// Rohe Bytes vom Server, roh weil SwiftTerm selbst mit Bytes arbeitet
    /// (ANSI-Codes, Farben — alles schon im Strom enthalten).
    nonisolated let ausgabe: AsyncStream<[UInt8]>
    private let ausgabeWeiterleiten: AsyncStream<[UInt8]>.Continuation

    /// Für SwiftUI: eine Ansicht kann `zustand` nicht einfach lesen (Actor-
    /// Grenze), beobachtet stattdessen diesen Strom in einem `.task`.
    nonisolated let zustandsStrom: AsyncStream<ConnectionState>
    private let zustandWeiterleiten: AsyncStream<ConnectionState>.Continuation

    private let geheimnisQuelle: () -> String

    init(host: Host, geheimnisQuelle: @escaping () -> String) {
        self.host = host
        self.geheimnisQuelle = geheimnisQuelle
        var ausgabeFortsetzung: AsyncStream<[UInt8]>.Continuation!
        self.ausgabe = AsyncStream { ausgabeFortsetzung = $0 }
        self.ausgabeWeiterleiten = ausgabeFortsetzung
        var zustandFortsetzung: AsyncStream<ConnectionState>.Continuation!
        self.zustandsStrom = AsyncStream { zustandFortsetzung = $0 }
        self.zustandWeiterleiten = zustandFortsetzung
    }

    // MARK: Verbinden

    func verbinden() {
        guard laufendeAufgabe == nil else { return }
        zustand = .verbindet
        laufendeAufgabe = Task { [weak self] in
            await self?.sitzungAusführen()
        }
    }

    func trennen() {
        laufendeAufgabe?.cancel()
        laufendeAufgabe = nil
        schreiber = nil
        zustand = .getrennt
    }

    /// Erneut verbinden, z. B. wenn die App aus dem Hintergrund zurückkommt.
    /// Dank `tmux` auf dem Server geht dabei nichts verloren — die Sitzung
    /// lebt dort weiter, dieser Client klinkt sich nur neu ein.
    func erneutVerbinden() {
        trennen()
        verbinden()
    }

    private func sitzungAusführen() async {
        do {
            let auth = try authentifizierung()
            let client = try await SSHClient.connect(
                to: SSHClientSettings(
                    host: host.adresse,
                    port: host.port,
                    authenticationMethod: auth,
                    // Niklas' Server sind ihm selbst bekannt (earth, Nova, Dell),
                    // deshalb hier bewusst ohne Fingerabdruck-Prüfung. Bei einem
                    // fremden Server müsste das durch eine echte Prüfung ersetzt
                    // werden (SSHHostKeyValidator.trustedKeys).
                    hostKeyValidator: .acceptAnything()
                )
            )

            zustand = .verbunden

            try await client.withPTY(
                SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: 80,
                    terminalRowHeight: 24,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([.ECHO: 1])
                )
            ) { [weak self] eingang, ausgang in
                guard let self else { return }
                await self.schreiberSetzen(ausgang)

                if !self.host.startBefehl.isEmpty {
                    try? await ausgang.write(ByteBuffer(string: self.host.startBefehl + "\n"))
                }

                for try await stück in eingang {
                    switch stück {
                    case .stdout(let puffer), .stderr(let puffer):
                        self.ausgabeWeiterleiten.yield(Array(puffer.readableBytesView))
                    }
                }
            }

            // Die Schleife endet normal, wenn die Shell beendet wurde.
            zustand = .getrennt
        } catch is CancellationError {
            // Absichtlich getrennt (trennen()/erneutVerbinden()) — kein Fehler.
        } catch {
            zustand = .fehlgeschlagen(Self.lesbarerFehler(error))
        }
        schreiber = nil
        laufendeAufgabe = nil
    }

    private func schreiberSetzen(_ schreiber: TTYStdinWriter) {
        self.schreiber = schreiber
    }

    // MARK: Senden

    /// Für die Befehlszeile unten: ein vollständiger Befehl samt Zeilenumbruch.
    /// Nutzt die normale iOS-Tastatur mit Autokorrektur.
    func zeileSenden(_ text: String) async {
        guard let schreiber else { return }
        try? await schreiber.write(ByteBuffer(string: text + "\n"))
    }

    /// Für den Rohmodus: jedes Zeichen einzeln, ohne Autokorrektur, direkt
    /// an den entfernten Prozess — nötig für vim, tmux-Navigation & Co.
    func rohSenden(_ bytes: [UInt8]) async {
        guard let schreiber else { return }
        try? await schreiber.write(ByteBuffer(bytes: bytes))
    }

    func größeÄndern(spalten: Int, zeilen: Int) async {
        guard let schreiber else { return }
        try? await schreiber.changeSize(cols: spalten, rows: zeilen, pixelWidth: 0, pixelHeight: 0)
    }

    // MARK: Authentifizierung

    private func authentifizierung() throws -> @Sendable () -> SSHAuthenticationMethod {
        let benutzer = host.benutzer
        let geheimnis = geheimnisQuelle()

        switch host.authArt {
        case .passwort:
            return { .passwordBased(username: benutzer, password: geheimnis) }
        case .schluessel:
            // Nur zur Probe parsen, damit ein kaputter Schlüssel sofort aussagekräftig
            // scheitert, statt erst beim Verbindungsaufbau mit einer rohen NIO-Meldung.
            let istEd25519 = (try? Curve25519.Signing.PrivateKey(sshEd25519: geheimnis)) != nil
            let istRSA = istEd25519 ? false : (try? Insecure.RSA.PrivateKey(sshRsa: geheimnis)) != nil
            guard istEd25519 || istRSA else { throw SSHVerbindungsFehler.schlüsselNichtLesbar }

            // Im Closure wird NUR der Text eingefangen (`String` ist nebenläufigkeitssicher)
            // und bei jedem Aufruf neu geparst — der geparste Schlüssel selbst
            // (`Insecure.RSA.PrivateKey`) ist es nicht und dürfte sonst nicht in ein
            // `@Sendable`-Closure wandern.
            return {
                if istEd25519, let schlüssel = try? Curve25519.Signing.PrivateKey(sshEd25519: geheimnis) {
                    return .ed25519(username: benutzer, privateKey: schlüssel)
                }
                if let schlüssel = try? Insecure.RSA.PrivateKey(sshRsa: geheimnis) {
                    return .rsa(username: benutzer, privateKey: schlüssel)
                }
                // Unerreichbar in der Praxis: oben schon erfolgreich geprüft.
                return .passwordBased(username: benutzer, password: "")
            }
        }
    }

    private static func lesbarerFehler(_ fehler: Error) -> String {
        // Citadel/NIO-Fehlertexte sind technisch — hier nur das Nötigste
        // herausgreifen, damit in der Tab-Leiste kein Roman steht.
        let text = "\(fehler)"
        if text.contains("authentication") || text.contains("Authentication") {
            return "Anmeldung fehlgeschlagen"
        }
        if text.contains("timed out") || text.contains("TimeoutError") {
            return "Zeitüberschreitung"
        }
        if text.contains("Connection refused") {
            return "Verbindung abgelehnt"
        }
        return "Verbindung fehlgeschlagen"
    }
}

enum SSHVerbindungsFehler: LocalizedError {
    case schlüsselNichtLesbar

    var errorDescription: String? {
        switch self {
        case .schlüsselNichtLesbar:
            "Der hinterlegte Schlüssel lässt sich nicht lesen (weder als Ed25519 noch als RSA)."
        }
    }
}
