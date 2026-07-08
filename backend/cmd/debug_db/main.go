package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	ctx := context.Background()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://backend_winter_waterfall_5807:BpXimItNqgwcS1i@localhost:5433/backend_winter_waterfall_5807?sslmode=disable"
	}

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("connect to database: %v", err)
	}
	defer pool.Close()

	fmt.Println("--- Active queries ---")
	rows, err := pool.Query(ctx, `
		SELECT pid, age(clock_timestamp(), query_start), state, wait_event_type, wait_event, query 
		FROM pg_stat_activity 
		WHERE state != 'idle' AND pid != pg_backend_pid()
	`)
	if err != nil {
		log.Fatalf("query pg_stat_activity: %v", err)
	}
	for rows.Next() {
		var pid int
		var duration string
		var state, waitType, waitEvent, query string
		var waitTypePtr, waitEventPtr *string
		waitTypePtr = &waitType
		waitEventPtr = &waitEvent
		if err := rows.Scan(&pid, &duration, &state, &waitTypePtr, &waitEventPtr, &query); err != nil {
			log.Fatalf("scan pg_stat_activity: %v", err)
		}
		wt := "nil"
		if waitTypePtr != nil {
			wt = *waitTypePtr
		}
		we := "nil"
		if waitEventPtr != nil {
			we = *waitEventPtr
		}
		fmt.Printf("PID: %d | Duration: %s | State: %s | WaitType: %s | WaitEvent: %s\nQuery: %s\n\n", pid, duration, state, wt, we, query)
	}
	rows.Close()

	fmt.Println("--- Blocked queries (Locks) ---")
	blockedRows, err := pool.Query(ctx, `
		SELECT
			blocked_locks.pid     AS blocked_pid,
			blocked_activity.query    AS blocked_statement,
			blocking_locks.pid    AS blocking_pid,
			blocking_activity.query   AS blocking_statement
		FROM  pg_catalog.pg_locks         blocked_locks
		JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
		JOIN pg_catalog.pg_locks         blocking_locks 
			ON blocking_locks.locktype = blocked_locks.locktype
			AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
			AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
			AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
			AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
			AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
			AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
			AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
			AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
			AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
			AND blocking_locks.pid != blocked_locks.pid
		JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
		WHERE NOT blocked_locks.granted
	`)
	if err != nil {
		log.Fatalf("query blocked queries: %v", err)
	}
	for blockedRows.Next() {
		var blockedPid, blockingPid int
		var blockedStatement, blockingStatement string
		if err := blockedRows.Scan(&blockedPid, &blockedStatement, &blockingPid, &blockingStatement); err != nil {
			log.Fatalf("scan blocked queries: %v", err)
		}
		fmt.Printf("Blocked PID: %d (Query: %s)\nBlocking PID: %d (Query: %s)\n\n", blockedPid, blockedStatement, blockingPid, blockingStatement)
	}
	blockedRows.Close()
}
