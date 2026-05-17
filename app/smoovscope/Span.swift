import Foundation

struct SpanRecord: Identifiable, Hashable {
    let rowid: Int64
    let traceID: String
    let spanID: String
    let parentSpanID: String
    let name: String
    let kind: Int
    let startNs: Int64
    let endNs: Int64
    let statusCode: Int
    let statusMessage: String
    let serviceName: String
    let attributesJSON: String
    let resourceJSON: String

    var id: Int64 { rowid }

    var durationNs: Int64 { max(0, endNs - startNs) }
    var durationMs: Double { Double(durationNs) / 1_000_000.0 }
    var start: Date { Date(timeIntervalSince1970: TimeInterval(startNs) / 1_000_000_000.0) }
}

/// A trace is a group of spans sharing a trace_id.
struct Trace: Identifiable, Hashable {
    let traceID: String
    let rootName: String
    let serviceName: String
    let spanCount: Int
    let startNs: Int64
    let endNs: Int64

    var id: String { traceID }
    var durationMs: Double { Double(max(0, endNs - startNs)) / 1_000_000.0 }
    var start: Date { Date(timeIntervalSince1970: TimeInterval(startNs) / 1_000_000_000.0) }
}
