package main

import (
	_ "embed"
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

//go:embed static/index.html
var homePageHTML []byte

// Anti-bot / anti-flood baseline for when this app is hit directly (bypassing
// cache-reverse-proxy's own rate limit): caps each client IP at 5 requests
// per second. Per-instance only (Cloud Run can run several instances), so it
// is a defense-in-depth backstop, not a substitute for Cloud Armor at a real
// load balancer -- see diagrams/architecture.md "Pontos de melhoria".
const (
	rateLimitWindow               = time.Second
	rateLimitMaxRequestsPerWindow = 5
)

var (
	requestTimestampsByClientIP = map[string][]time.Time{}
	rateLimitStateMutex         sync.Mutex
)

func clientIPFromRequest(r *http.Request) string {
	if forwardedFor := r.Header.Get("X-Forwarded-For"); forwardedFor != "" {
		return strings.TrimSpace(strings.Split(forwardedFor, ",")[0])
	}
	// r.RemoteAddr is "ip:port" -- strip the port, which is different on
	// every connection and would otherwise make each request look like a
	// different client, defeating the rate limit.
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func enforcePerIPRateLimit(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		clientIP := clientIPFromRequest(r)
		now := time.Now()
		cutoff := now.Add(-rateLimitWindow)

		rateLimitStateMutex.Lock()
		recentTimestamps := requestTimestampsByClientIP[clientIP][:0]
		for _, t := range requestTimestampsByClientIP[clientIP] {
			if t.After(cutoff) {
				recentTimestamps = append(recentTimestamps, t)
			}
		}
		if len(recentTimestamps) >= rateLimitMaxRequestsPerWindow {
			requestTimestampsByClientIP[clientIP] = recentTimestamps
			rateLimitStateMutex.Unlock()
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusTooManyRequests)
			fmt.Fprint(w, `{"detail":"Too many requests, devagar ai"}`)
			return
		}
		requestTimestampsByClientIP[clientIP] = append(recentTimestamps, now)
		rateLimitStateMutex.Unlock()

		next(w, r)
	}
}

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

func handleHomePageRoute(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(homePageHTML)
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
	router.HandleFunc("/", enforcePerIPRateLimit(handleHomePageRoute))
	router.HandleFunc("/fixed", enforcePerIPRateLimit(wrapHandlerWithMetrics(&fixedRouteMetrics, handleFixedTextRoute)))
	router.HandleFunc("/time", enforcePerIPRateLimit(wrapHandlerWithMetrics(&timeRouteMetrics, handleServerTimeRoute)))
	router.HandleFunc("/healthz", handleHealthCheckRoute)
	router.HandleFunc("/metrics", handlePrometheusMetricsRoute)

	listenAddress := ":8080"
	log.Printf("go-fixed-time-api listening on %s", listenAddress)
	if err := http.ListenAndServe(listenAddress, router); err != nil {
		log.Fatal(err)
	}
}
