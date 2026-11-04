import Foundation
import Observation
import Citadel
import NIO
import NIOSSH
import Crypto

/// Für SwiftUI: der aktuelle Verbindungszustand als beobachtbarer Wert.
///
/// Vorher gab es dafür einen `AsyncStream`, den zwei Stellen gleichzeitig
/// gelesen haben (Tab-Kachel und Terminal-Kopfzeile) -- ein `AsyncStream`
/// liefert aber jedes Element an GENAU EINEN wartenden Leser, abwechselnd.
/// Die beiden Ansichten sahen darum nie denselben Zustand, und die
/// Wiederverbinden-Entscheidung beim Zurückkommen aus dem Hintergrund traf
/// auf Grundlage eines halben, oft falschen Zustands. Ein einziges
/// `@Observable`-Objekt, das beide Ansichten direkt lesen, hat dieses
/// Problem grundsätzlich nicht -- Observation benachrichtigt JEDEN Leser.
@MainActor
@Observable
final class VerbindungsZustand {
    var wert: ConnectionState = .getrennt
    /// Ob überhaupt schon einmal ein Verbindungsversuch gestartet wurde --
    /// ohne das wäre `.getrennt` nicht von „noch nie versucht, verbindet
    /// gleich automatisch" zu unterscheiden, und ein „Erneut verbinden"-Knopf
    /// bliebe im allerersten Moment eines neu geöffneten Tabs kurz sichtbar.
    var jeVersucht = false
}

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

    /// Siehe `VerbindungsZustand` oben. `nonisolated`, weil das Objekt selbst
    /// `@MainActor` ist und seine Identität sich nie ändert -- SwiftUI liest
    /// `verbindung.beobachtbar.wert` direkt, ohne `await`.
    nonisolated let beobachtbar = VerbindungsZustand()

    private(set) var zustand: ConnectionState = .getrennt {
        didSet {
            let neu = zustand
            Task { @MainActor [beobachtbar] in beobachtbar.wert = neu }
        }
    }
    private var schreiber: TTYStdinWriter?
    private var laufendeAufgabe: Task<Void, Never>?

    /// Steigt bei jedem `verbinden()`-Aufruf. `sitzungAusführen` prüft am
    /// Ende, ob es noch die AKTUELLE Generation ist, bevor es `zustand`,
    /// `schreiber` oder `laufendeAufgabe` anfasst -- sonst könnte eine durch
    /// `trennen()` abgebrochene alte Aufgabe (Citadels `for try await` endet
    /// bei Abbruch normal, nicht mit `CancellationError`) den Verweis auf
    /// eine inzwischen neu gestartete Aufgabe überschreiben, und es liefen
    /// zwei `tmux attach` gleichzeitig in ein Terminal.
    private var generation = 0

    /// Ob überhaupt schon einmal versucht wurde zu verbinden. Nur beim
    /// ALLERERSTEN Mal darf eine Größenmeldung aus `TerminalViewRepresentable`
    /// automatisch verbinden (siehe `verbindenFallsNeu`) -- sonst würde JEDE
    /// Größenänderung (Tastatur auf/zu, Drehen, und das für ALLE offenen Tabs
    /// gleichzeitig, auch unsichtbare) nach einem Fehlschlag sofort einen
    /// neuen Versuch auslösen. Mit falschem oder leerem Passwort entstehen so
    /// in Minuten viele Fehlversuche -- genug, um von fail2ban auf dem Server
    /// gesperrt zu werden, und zwar auf ALLEN Ports, nicht nur SSH.
    private var jeVersucht = false

    /// Die Größe, mit der die PTY angefragt wird. Startet bei einem groben
    /// Schätzwert, wird aber von `verbinden(spalten:zeilen:)` auf die echte
    /// Größe des Terminal-Views gesetzt, BEVOR überhaupt verbunden wird --
    /// sonst zeichnen tmux & Co. ihren ersten Bildschirm für 80 Spalten,
    /// obwohl ein iPhone hochkant viel weniger Platz hat, und das nachträgliche
    /// Umgrößern reißt den schon gezeichneten Inhalt auseinander statt ihn
    /// sauber neu aufzubauen.
    private var spalten = 80
    private var zeilen = 24

    /// Rohe Bytes vom Server, roh weil SwiftTerm selbst mit Bytes arbeitet
    /// (ANSI-Codes, Farben — alles schon im Strom enthalten).
    nonisolated let ausgabe: AsyncStream<[UInt8]>
    private let ausgabeWeiterleiten: AsyncStream<[UInt8]>.Continuation

    /// Liest IMMER frisch aus dem Schlüsselbund, nicht nur einmal beim Öffnen
    /// des Tabs -- sonst nutzt jeder Wiederverbindungsversuch (auch die
    /// automatischen) für die Lebensdauer des Tabs weiter das Passwort von
    /// genau dem Moment, in dem der Tab geöffnet wurde. Trägt man es danach
    /// im Bearbeiten-Formular nach, würde der offene Tab trotzdem mit dem
    /// alten (oft leeren) Geheimnis weiterprobieren.
    private let geheimnisQuelle: () -> String

    init(host: Host, geheimnisQuelle: @escaping () -> String) {
        self.host = host
        self.geheimnisQuelle = geheimnisQuelle
        var ausgabeFortsetzung: AsyncStream<[UInt8]>.Continuation!
        self.ausgabe = AsyncStream { ausgabeFortsetzung = $0 }
        self.ausgabeWeiterleiten = ausgabeFortsetzung
    }

    // MARK: Verbinden

    /// Ob schon verbunden wird oder bereits verbunden ist.
    var istAktiv: Bool { laufendeAufgabe != nil }

    /// Für `TerminalViewRepresentable.Koordinator.sizeChanged`: Verbindet nur
    /// beim ALLERERSTEN Mal automatisch. Jeder weitere Fehlschlag braucht
    /// einen bewussten, von Niklas selbst ausgelösten erneuten Versuch --
    /// siehe Erklärung bei `jeVersucht`.
    func verbindenFallsNeu(spalten: Int, zeilen: Int) {
        guard !jeVersucht else { return }
        verbinden(spalten: spalten, zeilen: zeilen)
    }

    /// `spalten`/`zeilen` kommen von SwiftTerms erster echter Größenmeldung
    /// (siehe `TerminalViewRepresentable`) -- bleiben sie weg, etwa beim
    /// automatischen Wiederverbinden, gilt die zuletzt bekannte Größe weiter.
    func verbinden(spalten: Int? = nil, zeilen: Int? = nil) {
        guard laufendeAufgabe == nil else { return }
        jeVersucht = true
        Task { @MainActor [beobachtbar] in beobachtbar.jeVersucht = true }
        if let spalten { self.spalten = spalten }
        if let zeilen { self.zeilen = zeilen }
        zustand = .verbindet
        generation += 1
        let eigeneGeneration = generation
        laufendeAufgabe = Task { [weak self] in
            await self?.sitzungAusführen(generation: eigeneGeneration)
        }
    }

    func trennen() {
        laufendeAufgabe?.cancel()
        laufendeAufgabe = nil
        schreiber = nil
        zustand = .getrennt
    }

    /// Bewusst erneut verbinden -- z. B. ein eigener "Erneut verbinden"-Knopf
    /// nach einem Fehlschlag, oder wenn die App aus dem Hintergrund zurück-
    /// kommt. Dank `tmux` auf dem Server geht dabei nichts verloren — die
    /// Sitzung lebt dort weiter, dieser Client klinkt sich nur neu ein. Im
    /// Unterschied zu `verbindenFallsNeu` IMMER erlaubt, weil hier ein Mensch
    /// die Entscheidung trifft, nicht eine Größenänderung.
    func erneutVerbinden() {
        trennen()
        verbinden()
    }

    private func sitzungAusführen(generation eigeneGeneration: Int) async {
        var ssh: SSHClient?
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
            ssh = client

            // Absichtlich KEIN frühes `return` ab hier, wenn die Generation
            // schon nicht mehr passt -- sonst würde das Schließen der
            // Verbindung ganz unten übersprungen und die TCP-Verbindung
            // bliebe offen. Ein `if` statt `guard` lässt die Ausführung immer
            // bis zum Aufräumen am Ende durchlaufen.
            if generation == eigeneGeneration {
                zustand = .verbunden

                try await client.withPTY(
                    SSHChannelRequestEvent.PseudoTerminalRequest(
                        wantReply: true,
                        term: "xterm-256color",
                        terminalCharacterWidth: spalten,
                        terminalRowHeight: zeilen,
                        terminalPixelWidth: 0,
                        terminalPixelHeight: 0,
                        terminalModes: .init([.ECHO: 1])
                    )
                ) { [weak self] eingang, ausgang in
                    guard let self else { return }
                    await self.schreiberSetzen(ausgang, generation: eigeneGeneration)

                    if !self.host.startBefehl.isEmpty {
                        try? await ausgang.write(ByteBuffer(string: self.host.startBefehl + "\n"))
                    }

                    for try await stück in eingang {
                        guard await self.generation == eigeneGeneration else { return }
                        switch stück {
                        case .stdout(let puffer), .stderr(let puffer):
                            self.ausgabeWeiterleiten.yield(Array(puffer.readableBytesView))
                        }
                    }
                }

                if generation == eigeneGeneration {
                    // Die Schleife endet normal, wenn die Shell beendet wurde.
                    zustand = .getrennt
                }
            }
        } catch is CancellationError {
            // Absichtlich getrennt (trennen()/erneutVerbinden()) — kein Fehler.
        } catch {
            if generation == eigeneGeneration {
                zustand = .fehlgeschlagen(Self.lesbarerFehler(error))
            }
        }
        // `withPTY` schließt nur den Kanal, nicht die Verbindung selbst --
        // ohne das hier bliebe bei jedem Tab-Schließen und jedem erneuten
        // Verbinden eine TCP-Verbindung samt sshd-Prozess auf dem Server offen.
        // Läuft IMMER, auch wenn die Generation inzwischen überholt ist.
        try? await ssh?.close()
        if generation == eigeneGeneration {
            schreiber = nil
            laufendeAufgabe = nil
        }
    }

    private func schreiberSetzen(_ schreiber: TTYStdinWriter, generation eigeneGeneration: Int) {
        guard generation == eigeneGeneration else { return }
        self.schreiber = schreiber
    }

    // MARK: Senden

    /// Jedes Zeichen einzeln, direkt an den entfernten Prozess — so wie ein
    /// echtes Terminal es erwartet, inklusive vim, tmux-Navigation & Co.
    func rohSenden(_ bytes: [UInt8]) async {
        guard let schreiber else { return }
        try? await schreiber.write(ByteBuffer(bytes: bytes))
    }

    func größeÄndern(spalten: Int, zeilen: Int) async {
        self.spalten = spalten
        self.zeilen = zeilen
        guard let schreiber else { return }
        try? await schreiber.changeSize(cols: spalten, rows: zeilen, pixelWidth: 0, pixelHeight: 0)
    }

    // MARK: Authentifizierung

    private func authentifizierung() throws -> @Sendable () -> SSHAuthenticationMethod {
        let benutzer = host.benutzer
        // `\r` (Windows-Zeilenenden, z. B. nach dem Kopieren aus manchen Apps)
        // und Leerraum am Rand lassen sowohl die Base64-Dekodierung eines
        // Schlüssels als auch, bei Passwörtern, eine unsichtbare Leerstelle
        // am Ende scheitern. Einmal hier bereinigen deckt beide Fälle ab.
        let geheimnis = geheimnisQuelle()
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch host.authArt {
        case .passwort:
            return { .passwordBased(username: benutzer, password: geheimnis) }
        case .schluessel:
            // Nur zur Probe parsen, damit ein kaputter Schlüssel sofort aussagekräftig
            // scheitert, statt erst beim Verbindungsaufbau mit einer rohen NIO-Meldung.
            var letzterFehler: Error?
            var istEd25519 = false
            do {
                _ = try Curve25519.Signing.PrivateKey(sshEd25519: geheimnis)
                istEd25519 = true
            } catch {
                letzterFehler = error
            }
            var istRSA = false
            if !istEd25519 {
                do {
                    _ = try Insecure.RSA.PrivateKey(sshRsa: geheimnis)
                    istRSA = true
                } catch {
                    letzterFehler = error
                }
            }
            guard istEd25519 || istRSA else {
                // Citadel wirft hierfür intern `OpenSSH.KeyError.missingDecryptionKey`,
                // aber dieser Typ ist nicht `public` und darum von hier aus nicht
                // auffangbar -- nur an der Fehlerbeschreibung zu erkennen.
                if let letzterFehler, "\(letzterFehler)".contains("missingDecryptionKey") {
                    throw SSHVerbindungsFehler.schlüsselBrauchtPassphrase
                }
                throw SSHVerbindungsFehler.schlüsselNichtLesbar
            }

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
        // Eigene Fehler (z. B. SSHVerbindungsFehler) haben eine passende
        // Beschreibung -- die muss zuerst geprüft werden, sonst verdeckt die
        // folgende generische Textsuche sie immer.
        if let eigener = fehler as? LocalizedError, let text = eigener.errorDescription {
            return text
        }
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
    case schlüsselBrauchtPassphrase

    var errorDescription: String? {
        switch self {
        case .schlüsselNichtLesbar:
            "Der hinterlegte Schlüssel lässt sich nicht lesen (weder als Ed25519 noch als RSA)."
        case .schlüsselBrauchtPassphrase:
            "Dieser Schlüssel ist mit einer Passphrase geschützt -- das unterstützt Anker noch nicht. Bitte einen Schlüssel ohne Passphrase hinterlegen."
        }
    }
}
