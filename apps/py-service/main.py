from datetime import datetime, timezone

from fastapi import FastAPI, Response
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = FastAPI(title="py-service")

REQUEST_COUNT = Counter(
    "app_requests_total", "Total requests received", ["route"]
)
REQUEST_LATENCY = Histogram(
    "app_request_latency_seconds", "Request latency in seconds", ["route"]
)


@app.get("/fixed")
@REQUEST_LATENCY.labels(route="/fixed").time()
def fixed():
    REQUEST_COUNT.labels(route="/fixed").inc()
    return {"service": "py-service", "message": "Hello from the Python service"}


@app.get("/time")
@REQUEST_LATENCY.labels(route="/time").time()
def server_time():
    REQUEST_COUNT.labels(route="/time").inc()
    return {"service": "py-service", "server_time": datetime.now(timezone.utc).isoformat()}


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
