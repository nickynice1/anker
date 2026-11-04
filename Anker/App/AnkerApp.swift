import SwiftUI

@main
struct AnkerApp: App {
    @State private var hosts = HostsStore()
    @State private var sitzungen = SessionsManager()

    var body: some Scene {
        WindowGroup {
            TerminalTabsView(sitzungen: sitzungen, hosts: hosts)
                .preferredColorScheme(.dark)
        }
    }
}
