package main

import (
	"fmt"
	"log"
	"net/http"
	"sync/atomic"
	"time"
)

type routeMetrics struct {
	count       int64
	latencySumUs int64
}

var (
	fixedMetrics routeMetrics
	timeMetrics  routeMetrics
)

func instrument(route string, m *routeMetrics, handler http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		handler(w, r)
		atomic.AddInt64(&m.count, 1)
		atomic.AddInt64(&m.latencySumUs, time.Since(start).Microseconds())
	}
}

func fixedHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"service":"go-service","message":"Hello from the Go service"}`)
}

func timeHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"service":"go-service","server_time":"%s"}`, time.Now().UTC().Format(time.RFC3339Nano))
}

func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprint(w, `{"status":"ok"}`)
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")

	fc := atomic.LoadInt64(&fixedMetrics.count)
	fl := atomic.LoadInt64(&fixedMetrics.latencySumUs)
	tc := atomic.LoadInt64(&timeMetrics.count)
	tl := atomic.LoadInt64(&timeMetrics.latencySumUs)

	fmt.Fprintln(w, "# HELP app_requests_total Total requests received")
	fmt.Fprintln(w, "# TYPE app_requests_total counter")
	fmt.Fprintf(w, "app_requests_total{route=\"/fixed\"} %d\n", fc)
	fmt.Fprintf(w, "app_requests_total{route=\"/time\"} %d\n", tc)

	fmt.Fprintln(w, "# HELP app_request_latency_microseconds_sum Sum of request latency in microseconds")
	fmt.Fprintln(w, "# TYPE app_request_latency_microseconds_sum counter")
	fmt.Fprintf(w, "app_request_latency_microseconds_sum{route=\"/fixed\"} %d\n", fl)
	fmt.Fprintf(w, "app_request_latency_microseconds_sum{route=\"/time\"} %d\n", tl)
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/fixed", instrument("/fixed", &fixedMetrics, fixedHandler))
	mux.HandleFunc("/time", instrument("/time", &timeMetrics, timeHandler))
	mux.HandleFunc("/healthz", healthzHandler)
	mux.HandleFunc("/metrics", metricsHandler)

	addr := ":8080"
	log.Printf("go-service listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
