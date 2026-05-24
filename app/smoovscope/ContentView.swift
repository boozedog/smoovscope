import SwiftUI

struct ContentView: View {
    @Environment(Runtime.self) private var runtime
    @State private var selectedTraceID: String?

    var body: some View {
        NavigationSplitView {
            TraceListView(selectedTraceID: $selectedTraceID)
        } detail: {
            if let id = selectedTraceID {
                TraceDetailView(traceID: id)
            } else {
                ContentUnavailableView(
                    "No trace selected",
                    systemImage: "waveform.path.ecg",
                    description: Text(runtime.status),
                )
            }
        }
        .navigationTitle("smoovscope")
        .toolbar {
            ToolbarItem(placement: .status) {
                Text(runtime.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TraceListView: View {
    @Environment(Runtime.self) private var runtime
    @Binding var selectedTraceID: String?

    var body: some View {
        List(selection: $selectedTraceID) {
            ForEach(runtime.store.traces) { trace in
                VStack(alignment: .leading, spacing: 2) {
                    Text(trace.rootName)
                        .font(.body)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(trace.serviceName.isEmpty ? "—" : trace.serviceName)
                        Text("\(trace.spanCount) span\(trace.spanCount == 1 ? "" : "s")")
                        Text(String(format: "%.1f ms", trace.durationMs))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .tag(trace.traceID)
            }
        }
        .navigationTitle("Traces")
        .overlay {
            if runtime.store.traces.isEmpty {
                ContentUnavailableView(
                    "Waiting for spans",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Send OTLP/HTTP traces to 127.0.0.1:4318"),
                )
            }
        }
    }
}

struct TraceDetailView: View {
    @Environment(Runtime.self) private var runtime
    let traceID: String

    var body: some View {
        let items = runtime.store.spanTree(forTrace: traceID)
        let spans = items.map(\.span)
        let start = spans.map(\.startNs).min() ?? 0
        let end = spans.map(\.endNs).max() ?? 0
        let totalNs = max(1, end - start)
        let rootName = items.first(where: { $0.depth == 0 })?.span.name ?? "Trace"

        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(traceID)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                ForEach(items) { item in
                    SpanRow(
                        span: item.span,
                        depth: item.depth,
                        traceStartNs: start,
                        totalNs: totalNs,
                    )
                }
            }
            .padding()
        }
        .navigationTitle(rootName)
    }
}

struct SpanRow: View {
    let span: SpanRecord
    let depth: Int
    let traceStartNs: Int64
    let totalNs: Int64

    private static let indentStep: CGFloat = 16

    var body: some View {
        let offset = Double(span.startNs - traceStartNs) / Double(totalNs)
        let width = max(0.002, Double(span.durationNs) / Double(totalNs))
        let indent = CGFloat(depth) * Self.indentStep

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Color.clear.frame(width: indent)
                Text(span.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: "%.2f ms", span.durationMs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                Rectangle()
                    .fill(span.statusCode == 2 ? Color.red : Color.accentColor)
                    .frame(width: max(2, w * width), height: 10)
                    .offset(x: indent + (w - indent) * offset)
            }
            .frame(height: 10)
        }
        .padding(.vertical, 2)
    }
}
