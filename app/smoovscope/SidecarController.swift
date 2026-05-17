import Foundation

enum SidecarError: Error, LocalizedError {
    case binaryNotFound

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "otlp-receiver binary not found in app bundle Resources/"
        }
    }
}

/// Launches and supervises the Go OTLP receiver process.
final class SidecarController {
    private var process: Process?

    func start(databasePath: String, address: String = "127.0.0.1:4318") throws {
        guard let url = Bundle.main.url(forResource: "otlp-receiver", withExtension: nil) else {
            throw SidecarError.binaryNotFound
        }

        let p = Process()
        p.executableURL = url
        p.arguments = ["-db", databasePath, "-addr", address]

        // Forward stdout/stderr to the app's console for now.
        p.standardOutput = FileHandle.standardOutput
        p.standardError = FileHandle.standardError

        try p.run()
        self.process = p
    }

    func stop() {
        process?.terminate()
        process?.waitUntilExit()
        process = nil
    }

    deinit { stop() }
}
