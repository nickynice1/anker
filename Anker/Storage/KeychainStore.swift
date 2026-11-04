import Foundation
import Security

/// Dünner, geprüfter Wrapper um den iOS-Schlüsselbund. Passwörter und
/// private Schlüssel laufen NUR hier durch, nie durch UserDefaults oder eine
/// eigene Datei. `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` heißt: nicht
/// im iCloud-Backup, nicht auf einem anderen Gerät lesbar, nur wenn das
/// Telefon entsperrt ist.
enum KeychainStore {
    private static let dienst = "de.niklasbergmann.anker"

    enum Fehler: Error {
        case schreibenFehlgeschlagen(OSStatus)
        case lesenFehlgeschlagen(OSStatus)
    }

    static func speichern(_ wert: String, für schlüssel: String) throws {
        let daten = Data(wert.utf8)
        var abfrage: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: schlüssel,
        ]
        SecItemDelete(abfrage as CFDictionary)
        abfrage[kSecValueData as String] = daten
        abfrage[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(abfrage as CFDictionary, nil)
        guard status == errSecSuccess else { throw Fehler.schreibenFehlgeschlagen(status) }
    }

    static func lesen(_ schlüssel: String) throws -> String? {
        let abfrage: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: schlüssel,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var ergebnis: AnyObject?
        let status = SecItemCopyMatching(abfrage as CFDictionary, &ergebnis)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let daten = ergebnis as? Data else {
            throw Fehler.lesenFehlgeschlagen(status)
        }
        return String(data: daten, encoding: .utf8)
    }

    static func löschen(_ schlüssel: String) {
        let abfrage: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: dienst,
            kSecAttrAccount as String: schlüssel,
        ]
        SecItemDelete(abfrage as CFDictionary)
    }
}
