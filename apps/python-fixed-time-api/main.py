import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock

from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = FastAPI(title="python-fixed-time-api")

HOME_PAGE_HTML = (Path(__file__).parent / "static" / "index.html").read_text(encoding="utf-8")

REQUEST_COUNT = Counter(
    "app_requests_total", "Total requests received", ["route"]
)
REQUEST_LATENCY = Histogram(
    "app_request_latency_seconds", "Request latency in seconds", ["route"]
)

# Anti-bot / anti-flood baseline for when this app is hit directly (bypassing
# cache-reverse-proxy's own rate limit): caps each client IP at 5 requests
# per second. Per-instance only (Cloud Run can run several instances), so it
# is a defense-in-depth backstop, not a substitute for Cloud Armor at a real
# load balancer -- see diagrams/architecture.md "Pontos de melhoria".
RATE_LIMIT_WINDOW_SECONDS = 1.0
RATE_LIMIT_MAX_REQUESTS_PER_WINDOW = 5
request_timestamps_by_client_ip = defaultdict(list)
rate_limit_state_lock = Lock()


def client_ip_from_request(request: Request) -> str:
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


@app.middleware("http")
async def enforce_per_ip_rate_limit(request: Request, call_next):
    client_ip = client_ip_from_request(request)
    now = time.monotonic()
    cutoff = now - RATE_LIMIT_WINDOW_SECONDS

    with rate_limit_state_lock:
        recent_timestamps = [t for t in request_timestamps_by_client_ip[client_ip] if t >= cutoff]
        if len(recent_timestamps) >= RATE_LIMIT_MAX_REQUESTS_PER_WINDOW:
            request_timestamps_by_client_ip[client_ip] = recent_timestamps
            return JSONResponse(status_code=429, content={"detail": "Too many requests, devagar ai"})
        recent_timestamps.append(now)
        request_timestamps_by_client_ip[client_ip] = recent_timestamps

    return await call_next(request)


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
