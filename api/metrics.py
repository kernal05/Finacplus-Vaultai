# Wraps the existing FastAPI app from main.py with proper HTTP metrics —
# request count + latency histogram broken out by method/path/status.
# main.py is never modified; the Dockerfile's uvicorn entrypoint points
# here instead of at main:app.

import time
from prometheus_client import Counter, Histogram
from starlette.middleware.base import BaseHTTPMiddleware

from main import app  # noqa: F401  (re-exported below)

REQUEST_COUNT = Counter(
    "vaultai_http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)

REQUEST_LATENCY = Histogram(
    "vaultai_http_request_duration_seconds",
    "HTTP request latency",
    ["method", "path"],
    buckets=(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30),
)

ANTHROPIC_CALLS = Counter(
    "vaultai_anthropic_calls_total",
    "Calls made to the Anthropic API",
    ["endpoint", "status"],
)


class MetricsMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        start = time.perf_counter()
        response = await call_next(request)
        duration = time.perf_counter() - start

        route = request.scope.get("route")
        path = route.path if route else request.url.path

        REQUEST_COUNT.labels(
            method=request.method, path=path, status=response.status_code
        ).inc()
        REQUEST_LATENCY.labels(method=request.method, path=path).observe(duration)

        return response


app.add_middleware(MetricsMiddleware)
