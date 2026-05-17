import SwiftUI

@main
struct SmoovscopeApp: App {
    @State private var runtime = Runtime()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(runtime)
                .task {
                    await runtime.start()
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Reveal Database in Finder") {
                    runtime.revealDatabase()
                }
            }
        }
    }
}
