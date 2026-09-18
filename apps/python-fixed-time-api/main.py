from datetime import datetime, timezone

from fastapi import FastAPI, Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = FastAPI(title="python-fixed-time-api")

REQUEST_COUNT = Counter(
    "app_requests_total", "Total requests received", ["route"]
)
REQUEST_LATENCY = Histogram(
    "app_request_latency_seconds", "Request latency in seconds", ["route"]
)


@app.get("/fixed")
@REQUEST_LATENCY.labels(route="/fixed").time()
def handle_fixed_text_route():
    REQUEST_COUNT.labels(route="/fixed").inc()
    return {"service": "python-fixed-time-api", "message": "Hello from the Python service"}


@app.get("/time")
@REQUEST_LATENCY.labels(route="/time").time()
def handle_server_time_route():
    REQUEST_COUNT.labels(route="/time").inc()
    return {"service": "python-fixed-time-api", "server_time": datetime.now(timezone.utc).isoformat()}


@app.get("/healthz")
def handle_health_check_route():
    return {"status": "ok"}


@app.get("/metrics")
def handle_prometheus_metrics_route():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
