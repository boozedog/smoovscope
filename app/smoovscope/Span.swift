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

    var isRootParent: Bool {
        parentSpanID.isEmpty || parentSpanID.allSatisfy { $0 == "0" }
    }
}

/// A span positioned in its trace tree for nested waterfall display.
struct SpanTreeItem: Identifiable, Hashable {
    let span: SpanRecord
    let depth: Int

    var id: Int64 { span.id }
}

extension Array where Element == SpanRecord {
    /// Depth-first tree order using OTLP parent links. Orphans become roots.
    func nestedSpanItems() -> [SpanTreeItem] {
        guard !isEmpty else { return [] }

        let byID = Dictionary(uniqueKeysWithValues: map { ($0.spanID, $0) })
        var childrenByParent: [String: [SpanRecord]] = [:]
        var roots: [SpanRecord] = []

        for span in self {
            if span.isRootParent || byID[span.parentSpanID] == nil {
                roots.append(span)
            } else {
                childrenByParent[span.parentSpanID, default: []].append(span)
            }
        }

        roots.sort { $0.startNs < $1.startNs }
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort { $0.startNs < $1.startNs }
        }

        var items: [SpanTreeItem] = []
        func walk(_ span: SpanRecord, depth: Int) {
            items.append(SpanTreeItem(span: span, depth: depth))
            for child in childrenByParent[span.spanID] ?? [] {
                walk(child, depth: depth + 1)
            }
        }
        for root in roots {
            walk(root, depth: 0)
        }
        return items
    }
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
