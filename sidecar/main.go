package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	coltracepb "go.opentelemetry.io/proto/otlp/collector/trace/v1"
	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	tracepb "go.opentelemetry.io/proto/otlp/trace/v1"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:4318", "OTLP/HTTP bind address")
	dbPath := flag.String("db", "smoovscope.sqlite", "SQLite database path")
	flag.Parse()

	store, err := openStore(*dbPath)
	if err != nil {
		log.Fatalf("open store: %v", err)
	}
	defer store.Close()

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/traces", handleTraces(store))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	srv := &http.Server{
		Addr:              *addr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Printf("smoovscope sidecar listening on %s (db=%s)", *addr, *dbPath)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("listen: %v", err)
		}
	}()

	<-ctx.Done()
	log.Printf("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
}

func handleTraces(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		defer r.Body.Close()

		var req coltracepb.ExportTraceServiceRequest
		ct, _, _ := strings.Cut(r.Header.Get("Content-Type"), ";")
		ct = strings.TrimSpace(ct)
		switch ct {
		case "application/x-protobuf", "":
			if err := proto.Unmarshal(body, &req); err != nil {
				http.Error(w, "invalid protobuf: "+err.Error(), http.StatusBadRequest)
				return
			}
		case "application/json":
			if err := (protojson.UnmarshalOptions{DiscardUnknown: true}).Unmarshal(body, &req); err != nil {
				http.Error(w, "invalid json: "+err.Error(), http.StatusBadRequest)
				return
			}
		default:
			http.Error(w, "unsupported content-type: "+ct, http.StatusUnsupportedMediaType)
			return
		}

		count, err := store.InsertExport(r.Context(), &req)
		if err != nil {
			log.Printf("insert: %v", err)
			http.Error(w, "store error", http.StatusInternalServerError)
			return
		}
		log.Printf("ingested %d spans", count)

		// OTLP response: empty ExportTraceServiceResponse on success
		resp, _ := proto.Marshal(&coltracepb.ExportTraceServiceResponse{})
		w.Header().Set("Content-Type", "application/x-protobuf")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(resp)
	}
}

// spanRow is the flattened representation we persist.
type spanRow struct {
	TraceID       string
	SpanID        string
	ParentSpanID  string
	Name          string
	Kind          int32
	StartNs       int64
	EndNs         int64
	StatusCode    int32
	StatusMessage string
	ServiceName   string
	Attributes    string // JSON
	Resource      string // JSON
}

func flattenSpans(req *coltracepb.ExportTraceServiceRequest) []spanRow {
	var rows []spanRow
	for _, rs := range req.GetResourceSpans() {
		service := serviceName(rs.GetResource().GetAttributes())
		resourceJSON := attrsToJSON(rs.GetResource().GetAttributes())
		for _, ss := range rs.GetScopeSpans() {
			for _, sp := range ss.GetSpans() {
				rows = append(rows, spanRow{
					TraceID:       hex.EncodeToString(sp.GetTraceId()),
					SpanID:        hex.EncodeToString(sp.GetSpanId()),
					ParentSpanID:  hex.EncodeToString(sp.GetParentSpanId()),
					Name:          sp.GetName(),
					Kind:          int32(sp.GetKind()),
					StartNs:       int64(sp.GetStartTimeUnixNano()),
					EndNs:         int64(sp.GetEndTimeUnixNano()),
					StatusCode:    int32(sp.GetStatus().GetCode()),
					StatusMessage: sp.GetStatus().GetMessage(),
					ServiceName:   service,
					Attributes:    attrsToJSON(sp.GetAttributes()),
					Resource:      resourceJSON,
				})
				_ = tracepb.Span_SPAN_KIND_UNSPECIFIED // keep tracepb import used
			}
		}
	}
	return rows
}

func serviceName(attrs []*commonpb.KeyValue) string {
	for _, kv := range attrs {
		if kv.GetKey() == "service.name" {
			return kv.GetValue().GetStringValue()
		}
	}
	return ""
}

func attrsToJSON(attrs []*commonpb.KeyValue) string {
	m := make(map[string]any, len(attrs))
	for _, kv := range attrs {
		m[kv.GetKey()] = anyValue(kv.GetValue())
	}
	b, err := json.Marshal(m)
	if err != nil {
		return "{}"
	}
	return string(b)
}

func anyValue(v *commonpb.AnyValue) any {
	if v == nil {
		return nil
	}
	switch x := v.Value.(type) {
	case *commonpb.AnyValue_StringValue:
		return x.StringValue
	case *commonpb.AnyValue_BoolValue:
		return x.BoolValue
	case *commonpb.AnyValue_IntValue:
		return x.IntValue
	case *commonpb.AnyValue_DoubleValue:
		return x.DoubleValue
	case *commonpb.AnyValue_ArrayValue:
		out := make([]any, 0, len(x.ArrayValue.GetValues()))
		for _, vv := range x.ArrayValue.GetValues() {
			out = append(out, anyValue(vv))
		}
		return out
	case *commonpb.AnyValue_KvlistValue:
		out := make(map[string]any, len(x.KvlistValue.GetValues()))
		for _, kv := range x.KvlistValue.GetValues() {
			out[kv.GetKey()] = anyValue(kv.GetValue())
		}
		return out
	case *commonpb.AnyValue_BytesValue:
		return fmt.Sprintf("0x%x", x.BytesValue)
	}
	return nil
}
