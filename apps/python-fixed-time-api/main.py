from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Response
from fastapi.responses import HTMLResponse
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = FastAPI(title="python-fixed-time-api")

HOME_PAGE_HTML = (Path(__file__).parent / "static" / "index.html").read_text(encoding="utf-8")

REQUEST_COUNT = Counter(
    "app_requests_total", "Total requests received", ["route"]
)
REQUEST_LATENCY = Histogram(
    "app_request_latency_seconds", "Request latency in seconds", ["route"]
)


@app.get("/", response_class=HTMLResponse)
def handle_home_page():
    return HOME_PAGE_HTML


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
