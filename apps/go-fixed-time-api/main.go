package main

import (
	"fmt"
	"log"
	"net/http"
	"sync/atomic"
	"time"
)

// requestMetrics holds the running counters exposed on /metrics for a single route.
type requestMetrics struct {
	totalRequestCount        int64
	totalLatencyMicroseconds int64
}

var (
	fixedRouteMetrics requestMetrics
	timeRouteMetrics  requestMetrics
)

// wrapHandlerWithMetrics records the request count and cumulative latency for a route
// every time the wrapped handler is called.
func wrapHandlerWithMetrics(metrics *requestMetrics, handler http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		requestStartTime := time.Now()
		handler(w, r)
		atomic.AddInt64(&metrics.totalRequestCount, 1)
		atomic.AddInt64(&metrics.totalLatencyMicroseconds, time.Since(requestStartTime).Microseconds())
	}
}

func handleFixedTextRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"service":"go-fixed-time-api","message":"Hello from the Go service"}`)
}

func handleServerTimeRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprintf(w, `{"service":"go-fixed-time-api","server_time":"%s"}`, time.Now().UTC().Format(time.RFC3339Nano))
}

func handleHealthCheckRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	fmt.Fprint(w, `{"status":"ok"}`)
}

func handlePrometheusMetricsRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")

	fixedRequestCount := atomic.LoadInt64(&fixedRouteMetrics.totalRequestCount)
	fixedLatencySumMicroseconds := atomic.LoadInt64(&fixedRouteMetrics.totalLatencyMicroseconds)
	timeRequestCount := atomic.LoadInt64(&timeRouteMetrics.totalRequestCount)
	timeLatencySumMicroseconds := atomic.LoadInt64(&timeRouteMetrics.totalLatencyMicroseconds)

	fmt.Fprintln(w, "# HELP app_requests_total Total requests received")
	fmt.Fprintln(w, "# TYPE app_requests_total counter")
	fmt.Fprintf(w, "app_requests_total{route=\"/fixed\"} %d\n", fixedRequestCount)
	fmt.Fprintf(w, "app_requests_total{route=\"/time\"} %d\n", timeRequestCount)

	fmt.Fprintln(w, "# HELP app_request_latency_microseconds_sum Sum of request latency in microseconds")
	fmt.Fprintln(w, "# TYPE app_request_latency_microseconds_sum counter")
	fmt.Fprintf(w, "app_request_latency_microseconds_sum{route=\"/fixed\"} %d\n", fixedLatencySumMicroseconds)
	fmt.Fprintf(w, "app_request_latency_microseconds_sum{route=\"/time\"} %d\n", timeLatencySumMicroseconds)
}

func main() {
	router := http.NewServeMux()
	router.HandleFunc("/fixed", wrapHandlerWithMetrics(&fixedRouteMetrics, handleFixedTextRoute))
	router.HandleFunc("/time", wrapHandlerWithMetrics(&timeRouteMetrics, handleServerTimeRoute))
	router.HandleFunc("/healthz", handleHealthCheckRoute)
	router.HandleFunc("/metrics", handlePrometheusMetricsRoute)

	listenAddress := ":8080"
	log.Printf("go-fixed-time-api listening on %s", listenAddress)
	if err := http.ListenAndServe(listenAddress, router); err != nil {
		log.Fatal(err)
	}
}
