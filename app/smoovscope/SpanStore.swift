import Foundation
import SQLite3
import Observation

/// Reads spans from the SQLite file the Go sidecar writes to.
/// Polls every `pollInterval` seconds for new rows since the last seen rowid.
@Observable
@MainActor
final class SpanStore {
    private(set) var spans: [SpanRecord] = []
    private(set) var lastError: String?

    private var db: OpaquePointer?
    private var lastSeenRowid: Int64 = 0
    private var pollTask: Task<Void, Never>?
    private let pollInterval: Duration = .milliseconds(250)

    nonisolated init() {}

    func open(databasePath: String) throws {
        // Wait for the sidecar to create the file. The sidecar creates it on
        // startup, but we may race it — retry briefly.
        var attempts = 0
        while !FileManager.default.fileExists(atPath: databasePath) {
            attempts += 1
            if attempts > 50 { break } // ~5s
            try await_ms(100)
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(databasePath, &handle, flags, nil) == SQLITE_OK, let handle else {
            throw NSError(domain: "SpanStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "failed to open \(databasePath)"])
        }
        self.db = handle
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: self?.pollInterval ?? .milliseconds(250))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let db { sqlite3_close(db) }
        db = nil
    }

    private func pollOnce() async {
        guard let db else { return }
        let sql = """
            SELECT rowid, trace_id, span_id, parent_span_id, name, kind,
                   start_ns, end_ns, status_code, status_message, service_name,
                   attributes, resource
            FROM spans
            WHERE rowid > ?
            ORDER BY rowid ASC
            LIMIT 500
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            lastError = String(cString: sqlite3_errmsg(db))
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, lastSeenRowid)

        var batch: [SpanRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let span = SpanRecord(
                rowid:          sqlite3_column_int64(stmt, 0),
                traceID:        sqliteString(stmt, 1),
                spanID:         sqliteString(stmt, 2),
                parentSpanID:   sqliteString(stmt, 3),
                name:           sqliteString(stmt, 4),
                kind:           Int(sqlite3_column_int(stmt, 5)),
                startNs:        sqlite3_column_int64(stmt, 6),
                endNs:          sqlite3_column_int64(stmt, 7),
                statusCode:     Int(sqlite3_column_int(stmt, 8)),
                statusMessage:  sqliteString(stmt, 9),
                serviceName:    sqliteString(stmt, 10),
                attributesJSON: sqliteString(stmt, 11),
                resourceJSON:   sqliteString(stmt, 12),
            )
            batch.append(span)
            lastSeenRowid = max(lastSeenRowid, span.rowid)
        }
        if !batch.isEmpty {
            spans.append(contentsOf: batch)
        }
    }

    var traces: [Trace] {
        var grouped: [String: [SpanRecord]] = [:]
        for s in spans {
            grouped[s.traceID, default: []].append(s)
        }
        return grouped.map { (traceID, spans) -> Trace in
            let sorted = spans.sorted { $0.startNs < $1.startNs }
            let root = sorted.first { $0.isRootParent } ?? sorted[0]
            return Trace(
                traceID: traceID,
                rootName: root.name,
                serviceName: root.serviceName,
                spanCount: spans.count,
                startNs: sorted.first?.startNs ?? 0,
                endNs: sorted.map(\.endNs).max() ?? 0,
            )
        }
        .sorted { $0.startNs > $1.startNs }
    }

    func spans(forTrace traceID: String) -> [SpanRecord] {
        spans.filter { $0.traceID == traceID }.sorted { $0.startNs < $1.startNs }
    }

    func spanTree(forTrace traceID: String) -> [SpanTreeItem] {
        spans(forTrace: traceID).nestedSpanItems()
    }
}

private func sqliteString(_ stmt: OpaquePointer?, _ col: Int32) -> String {
    guard let cstr = sqlite3_column_text(stmt, col) else { return "" }
    return String(cString: cstr)
}

private func await_ms(_ ms: Int) throws {
    try? Task.checkCancellation()
    Thread.sleep(forTimeInterval: TimeInterval(ms) / 1000.0)
}
