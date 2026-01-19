"""FastAPI application for URL shortening service."""

import hashlib
import json
import os
from collections.abc import Generator
from contextlib import contextmanager
from typing import Any

import psycopg2
import psycopg2.extensions
import redis
from fastapi import FastAPI, HTTPException, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, HttpUrl

app = FastAPI()

# Prometheus metrics
http_requests_total = Counter(
    "http_requests_total", "Total HTTP requests", ["method", "endpoint", "status"]
)

http_request_duration_seconds = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "endpoint"],
)

urls_created_total = Counter("urls_created_total", "Total URLs created")

urls_clicked_total = Counter("urls_clicked_total", "Total URL clicks")

# Config from environment
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", 5432))
POSTGRES_DB = os.getenv("POSTGRES_DB", "urlshortener")
POSTGRES_USER = os.getenv("POSTGRES_USER", "urlshort")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "password123")
BASE_URL = os.getenv("BASE_URL", "http://localhost:8080")

# Redis connection
redis_client = redis.Redis(
    host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD, decode_responses=True
)


@contextmanager
def get_db() -> Generator[psycopg2.extensions.connection, None, None]:
    """Get database connection context manager.

    Yields:
        Database connection object.
    """
    conn = psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        database=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
    )
    try:
        yield conn
    finally:
        conn.close()


class URLCreate(BaseModel):
    """Request model for URL shortening."""

    url: HttpUrl
    custom_code: str | None = None


class URLResponse(BaseModel):
    """Response model for shortened URL."""

    short_url: str
    original_url: str
    short_code: str


def generate_short_code(url: str) -> str:
    """Generate a short code from URL hash.

    Args:
        url: The URL to generate a short code for.

    Returns:
        A 6-character short code derived from the URL hash.
    """
    hash_object = hashlib.md5(url.encode(), usedforsecurity=False)  # noqa: S324
    return hash_object.hexdigest()[:6]


def queue_jobs(short_code: str, original_url: str) -> None:
    """Push jobs to Redis queue.

    Args:
        short_code: The short code for the URL.
        original_url: The original URL being shortened.
    """
    jobs = [
        {"type": "qr_code", "short_code": short_code, "url": original_url},
        {"type": "screenshot", "short_code": short_code, "url": original_url},
        {"type": "metadata", "short_code": short_code, "url": original_url},
    ]

    for job in jobs:
        redis_client.rpush("job_queue", json.dumps(job))


@app.on_event("startup")
async def startup_event() -> None:
    """Initialize database tables."""
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS urls (
                    id SERIAL PRIMARY KEY,
                    short_code VARCHAR(10) UNIQUE NOT NULL,
                    original_url TEXT NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    clicks INTEGER DEFAULT 0
                )
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS jobs (
                    id SERIAL PRIMARY KEY,
                    short_code VARCHAR(10),
                    job_type VARCHAR(50),
                    status VARCHAR(20),
                    result JSONB,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
            conn.commit()


@app.get("/metrics")
async def metrics() -> Response:
    """Prometheus metrics endpoint.

    Returns:
        Prometheus metrics in text format.
    """
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/health")
async def health() -> dict[str, str]:
    """Health check endpoint.

    Returns:
        Dictionary with health status.
    """
    return {"status": "healthy"}


@app.get("/ready")
async def ready() -> dict[str, str]:
    """Readiness check endpoint.

    Returns:
        Dictionary with readiness status.

    Raises:
        HTTPException: If service is not ready.
    """
    try:
        redis_client.ping()
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        return {"status": "ready"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Not ready: {str(e)}") from e


@app.post("/shorten", response_model=URLResponse)
async def shorten_url(url_data: URLCreate) -> URLResponse:
    """Create a shortened URL.

    Args:
        url_data: The URL data containing the URL and optional custom code.

    Returns:
        URLResponse with the shortened URL information.

    Raises:
        HTTPException: If short code already exists or on error.
    """
    with http_request_duration_seconds.labels(
        method="POST", endpoint="/shorten"
    ).time():
        original_url = str(url_data.url)
        short_code = url_data.custom_code or generate_short_code(original_url)

        with get_db() as conn:
            with conn.cursor() as cur:
                try:
                    cur.execute(
                        "INSERT INTO urls (short_code, original_url) VALUES (%s, %s) ON CONFLICT (short_code) DO NOTHING RETURNING short_code",
                        (short_code, original_url),
                    )
                    result = cur.fetchone()
                    conn.commit()

                    if result is None:
                        http_requests_total.labels(
                            method="POST", endpoint="/shorten", status="409"
                        ).inc()
                        raise HTTPException(
                            status_code=409, detail="Short code already exists"
                        )

                    # Queue background jobs
                    queue_jobs(short_code, original_url)

                    # Track analytics event
                    redis_client.rpush(
                        "analytics_queue",
                        json.dumps({"event": "url_created", "short_code": short_code}),
                    )

                    urls_created_total.inc()
                    http_requests_total.labels(
                        method="POST", endpoint="/shorten", status="200"
                    ).inc()

                    return URLResponse(
                        short_url=f"{BASE_URL}/{short_code}",
                        original_url=original_url,
                        short_code=short_code,
                    )
                except HTTPException:
                    raise
                except Exception as e:
                    conn.rollback()
                    http_requests_total.labels(
                        method="POST", endpoint="/shorten", status="500"
                    ).inc()
                    raise HTTPException(status_code=500, detail=str(e)) from e


@app.get("/{short_code}")
async def redirect_url(short_code: str) -> dict[str, str]:
    """Redirect to original URL.

    Args:
        short_code: The short code to look up.

    Returns:
        Dictionary with redirect URL.

    Raises:
        HTTPException: If URL not found.
    """
    with http_request_duration_seconds.labels(
        method="GET", endpoint="/{short_code}"
    ).time():
        # Check cache first
        cached = redis_client.get(f"url:{short_code}")
        if cached:
            original_url = cached
        else:
            with get_db() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT original_url FROM urls WHERE short_code = %s",
                        (short_code,),
                    )
                    result = cur.fetchone()

                    if not result:
                        http_requests_total.labels(
                            method="GET", endpoint="/{short_code}", status="404"
                        ).inc()
                        raise HTTPException(status_code=404, detail="URL not found")

                    original_url = result[0]
                    # Cache for 1 hour
                    redis_client.setex(f"url:{short_code}", 3600, original_url)

                    # Increment click counter
                    cur.execute(
                        "UPDATE urls SET clicks = clicks + 1 WHERE short_code = %s",
                        (short_code,),
                    )
                    conn.commit()

        # Queue analytics event
        redis_client.rpush(
            "analytics_queue",
            json.dumps({"event": "url_clicked", "short_code": short_code}),
        )

        urls_clicked_total.inc()
        http_requests_total.labels(
            method="GET", endpoint="/{short_code}", status="200"
        ).inc()

        return {"redirect_url": original_url}


@app.get("/stats/{short_code}")
async def get_stats(short_code: str) -> dict[str, Any]:
    """Get statistics for a URL.

    Args:
        short_code: The short code to get stats for.

    Returns:
        Dictionary with URL statistics.

    Raises:
        HTTPException: If URL not found.
    """
    with http_request_duration_seconds.labels(
        method="GET", endpoint="/stats/{short_code}"
    ).time():
        with get_db() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT original_url, clicks, created_at FROM urls WHERE short_code = %s",
                    (short_code,),
                )
                result = cur.fetchone()

                if not result:
                    http_requests_total.labels(
                        method="GET", endpoint="/stats/{short_code}", status="404"
                    ).inc()
                    raise HTTPException(status_code=404, detail="URL not found")

                # Get job results
                cur.execute(
                    "SELECT job_type, status, result FROM jobs WHERE short_code = %s",
                    (short_code,),
                )
                jobs = cur.fetchall()

                http_requests_total.labels(
                    method="GET", endpoint="/stats/{short_code}", status="200"
                ).inc()

                return {
                    "short_code": short_code,
                    "original_url": result[0],
                    "clicks": result[1],
                    "created_at": result[2],
                    "jobs": [
                        {"type": j[0], "status": j[1], "result": j[2]} for j in jobs
                    ],
                }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
