import SwiftUI
import SpacebarKit

@main
struct SpacebarApp: App {
    init() {
        do {
            try Paths.ensureDirectories()
            try "spacebar app \(Host.version) wrote this at \(Date())\n"
                .write(to: Paths.markerFile, atomically: true, encoding: .utf8)
        } catch {
            NSLog("spacebar: could not write marker: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup("Spacebar") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Spacebar scaffold")
                Text(Paths.root.path).font(.caption).textSelection(.enabled)
            }
            .padding(40)
        }
    }
}
