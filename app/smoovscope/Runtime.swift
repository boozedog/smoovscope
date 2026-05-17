import Foundation
import AppKit
import Observation

/// Top-level container: owns the sidecar process and the span store.
@Observable
final class Runtime {
    let sidecar = SidecarController()
    let store = SpanStore()

    private(set) var dbURL: URL?
    private(set) var status: String = "starting"

    func start() async {
        do {
            let url = try Self.databaseURL()
            self.dbURL = url

            try sidecar.start(databasePath: url.path)
            try store.open(databasePath: url.path)
            store.startPolling()

            status = "listening on 127.0.0.1:4318"
        } catch {
            status = "error: \(error.localizedDescription)"
        }
    }

    func revealDatabase() {
        guard let dbURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dbURL])
    }

    static func databaseURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        let dir = appSupport.appendingPathComponent("smoovscope", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("traces.sqlite")
    }
}
