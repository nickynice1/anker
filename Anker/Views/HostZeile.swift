import SwiftUI

/// Eine Server-Zeile: Antippen öffnet ihn, der Ellipsen-Knopf führt zum
/// Bearbeiten-Formular. Von `HostListView` und der Startseite in
/// `TerminalTabsView` gemeinsam genutzt, damit beide gleich aussehen.
struct HostZeile: View {
    let host: Host
    let öffnen: () -> Void
    let bearbeiten: () -> Void

    var body: some View {
        Button(action: öffnen) {
            HStack(spacing: Theme.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text(host.name.prefix(1).uppercased())
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.name)
                        .font(Theme.headlineFont)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(host.benutzer)@\(host.adresse)")
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button(action: bearbeiten) {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
        .padding(.vertical, 4)
    }
}
