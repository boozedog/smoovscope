package main

import (
	"context"
	"database/sql"
	"fmt"

	coltracepb "go.opentelemetry.io/proto/otlp/collector/trace/v1"
	_ "modernc.org/sqlite"
)

const schema = `
CREATE TABLE IF NOT EXISTS spans (
    rowid          INTEGER PRIMARY KEY AUTOINCREMENT,
    trace_id       TEXT NOT NULL,
    span_id        TEXT NOT NULL,
    parent_span_id TEXT NOT NULL,
    name           TEXT NOT NULL,
    kind           INTEGER NOT NULL,
    start_ns       INTEGER NOT NULL,
    end_ns         INTEGER NOT NULL,
    status_code    INTEGER NOT NULL,
    status_message TEXT NOT NULL,
    service_name   TEXT NOT NULL,
    attributes     TEXT NOT NULL,
    resource       TEXT NOT NULL,
    received_at    INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000000000),
    UNIQUE(trace_id, span_id)
);

CREATE INDEX IF NOT EXISTS idx_spans_trace_id ON spans(trace_id);
CREATE INDEX IF NOT EXISTS idx_spans_start_ns ON spans(start_ns);
`

type Store struct {
	db *sql.DB
}

func openStore(path string) (*Store, error) {
	db, err := sql.Open("sqlite", path+"?_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)&_pragma=foreign_keys(ON)")
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("apply schema: %w", err)
	}
	return &Store{db: db}, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) InsertExport(ctx context.Context, req *coltracepb.ExportTraceServiceRequest) (int, error) {
	rows := flattenSpans(req)
	if len(rows) == 0 {
		return 0, nil
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	stmt, err := tx.PrepareContext(ctx, `
        INSERT OR IGNORE INTO spans
            (trace_id, span_id, parent_span_id, name, kind, start_ns, end_ns,
             status_code, status_message, service_name, attributes, resource)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)
	if err != nil {
		return 0, err
	}
	defer stmt.Close()

	for _, r := range rows {
		if _, err := stmt.ExecContext(ctx,
			r.TraceID, r.SpanID, r.ParentSpanID, r.Name, r.Kind,
			r.StartNs, r.EndNs, r.StatusCode, r.StatusMessage,
			r.ServiceName, r.Attributes, r.Resource,
		); err != nil {
			return 0, err
		}
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return len(rows), nil
}
