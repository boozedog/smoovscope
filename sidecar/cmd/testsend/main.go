// testsend sends a minimal OTLP/HTTP trace payload to the sidecar for smoke testing.
package main

import (
	"bytes"
	"crypto/rand"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	coltracepb "go.opentelemetry.io/proto/otlp/collector/trace/v1"
	commonpb "go.opentelemetry.io/proto/otlp/common/v1"
	resourcepb "go.opentelemetry.io/proto/otlp/resource/v1"
	tracepb "go.opentelemetry.io/proto/otlp/trace/v1"
	"google.golang.org/protobuf/proto"
)

func main() {
	endpoint := "http://127.0.0.1:4318/v1/traces"
	if len(os.Args) > 1 {
		endpoint = os.Args[1]
	}

	traceID := randBytes(16)
	rootID := randBytes(8)
	childID := randBytes(8)

	now := time.Now().UnixNano()
	startRoot := uint64(now)
	endRoot := uint64(now + int64(50*time.Millisecond))
	startChild := uint64(now + int64(5*time.Millisecond))
	endChild := uint64(now + int64(30*time.Millisecond))

	req := &coltracepb.ExportTraceServiceRequest{
		ResourceSpans: []*tracepb.ResourceSpans{{
			Resource: &resourcepb.Resource{
				Attributes: []*commonpb.KeyValue{
					strAttr("service.name", "smoke-test"),
					strAttr("service.version", "0.1.0"),
				},
			},
			ScopeSpans: []*tracepb.ScopeSpans{{
				Scope: &commonpb.InstrumentationScope{Name: "testsend"},
				Spans: []*tracepb.Span{
					{
						TraceId:           traceID,
						SpanId:            rootID,
						Name:              "GET /hello",
						Kind:              tracepb.Span_SPAN_KIND_SERVER,
						StartTimeUnixNano: startRoot,
						EndTimeUnixNano:   endRoot,
						Attributes: []*commonpb.KeyValue{
							strAttr("http.method", "GET"),
							strAttr("http.route", "/hello"),
						},
						Status: &tracepb.Status{Code: tracepb.Status_STATUS_CODE_OK},
					},
					{
						TraceId:           traceID,
						SpanId:            childID,
						ParentSpanId:      rootID,
						Name:              "db.query",
						Kind:              tracepb.Span_SPAN_KIND_CLIENT,
						StartTimeUnixNano: startChild,
						EndTimeUnixNano:   endChild,
						Attributes: []*commonpb.KeyValue{
							strAttr("db.system", "postgres"),
							strAttr("db.statement", "SELECT 1"),
						},
						Status: &tracepb.Status{Code: tracepb.Status_STATUS_CODE_OK},
					},
				},
			}},
		}},
	}

	body, err := proto.Marshal(req)
	if err != nil {
		log.Fatalf("marshal: %v", err)
	}

	resp, err := http.Post(endpoint, "application/x-protobuf", bytes.NewReader(body))
	if err != nil {
		log.Fatalf("post: %v", err)
	}
	defer resp.Body.Close()
	rb, _ := io.ReadAll(resp.Body)
	fmt.Printf("status=%s body=%d bytes\n", resp.Status, len(rb))
}

func strAttr(k, v string) *commonpb.KeyValue {
	return &commonpb.KeyValue{Key: k, Value: &commonpb.AnyValue{Value: &commonpb.AnyValue_StringValue{StringValue: v}}}
}

func randBytes(n int) []byte {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return b
}
