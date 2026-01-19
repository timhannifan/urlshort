"""Worker service for processing background jobs."""

import base64
import json
import os
import time
from collections.abc import Generator
from contextlib import contextmanager
from io import BytesIO

import psycopg2
import psycopg2.extensions
import qrcode
import redis
import requests
from prometheus_client import Counter, Histogram, start_http_server

# Config from environment
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", 5432))
POSTGRES_DB = os.getenv("POSTGRES_DB", "urlshortener")
POSTGRES_USER = os.getenv("POSTGRES_USER", "urlshort")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "password123")
WORKER_CONCURRENCY = int(os.getenv("WORKER_CONCURRENCY", 5))

# Redis connection
redis_client = redis.Redis(
    host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD, decode_responses=True
)

# Prometheus metrics
jobs_processed_total = Counter(
    "jobs_processed_total", "Total jobs processed", ["job_type", "status"]
)

job_processing_duration_seconds = Histogram(
    "job_processing_duration_seconds",
    "Job processing duration in seconds",
    ["job_type"],
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


def save_job_result(short_code: str, job_type: str, status: str, result: dict) -> None:
    """Save job result to database.

    Args:
        short_code: The short code associated with the job.
        job_type: The type of job.
        status: The status of the job.
        result: The result dictionary to save.
    """
    with get_db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO jobs (short_code, job_type, status, result)
                   VALUES (%s, %s, %s, %s)""",
                (short_code, job_type, status, json.dumps(result)),
            )
            conn.commit()


def process_qr_code(job: dict) -> None:
    """Generate QR code for the URL.

    Args:
        job: Dictionary containing job data with 'short_code' and 'url' keys.
    """
    print(f"Processing QR code for {job['short_code']}")
    with job_processing_duration_seconds.labels(job_type="qr_code").time():
        try:
            qr = qrcode.QRCode(version=1, box_size=10, border=5)
            qr.add_data(job["url"])
            qr.make(fit=True)

            img = qr.make_image(fill_color="black", back_color="white")

            # Convert to base64
            buffered = BytesIO()
            img.save(buffered, format="PNG")
            img_str = base64.b64encode(buffered.getvalue()).decode()

            result = {"qr_code": img_str, "format": "png"}
            save_job_result(job["short_code"], "qr_code", "completed", result)
            jobs_processed_total.labels(job_type="qr_code", status="completed").inc()
            print(f"QR code generated for {job['short_code']}")

        except Exception as e:
            print(f"Error generating QR code: {e}")
            save_job_result(job["short_code"], "qr_code", "failed", {"error": str(e)})
            jobs_processed_total.labels(job_type="qr_code", status="failed").inc()


def process_screenshot(job: dict) -> None:
    """Take screenshot of URL (simplified version).

    Args:
        job: Dictionary containing job data with 'short_code' and 'url' keys.
    """
    print(f"Processing screenshot for {job['short_code']}")
    with job_processing_duration_seconds.labels(job_type="screenshot").time():
        try:
            # In a real implementation, you'd use Puppeteer/Playwright
            # For this demo, we'll just simulate it
            time.sleep(2)  # Simulate processing time

            result = {
                "screenshot_url": f"https://placeholder.com/screenshot/{job['short_code']}",
                "status": "simulated",
            }
            save_job_result(job["short_code"], "screenshot", "completed", result)
            jobs_processed_total.labels(job_type="screenshot", status="completed").inc()
            print(f"Screenshot processed for {job['short_code']}")

        except Exception as e:
            print(f"Error taking screenshot: {e}")
            save_job_result(
                job["short_code"], "screenshot", "failed", {"error": str(e)}
            )
            jobs_processed_total.labels(job_type="screenshot", status="failed").inc()


def process_metadata(job: dict) -> None:
    """Fetch metadata/OpenGraph data from URL.

    Args:
        job: Dictionary containing job data with 'short_code' and 'url' keys.
    """
    print(f"Processing metadata for {job['short_code']}")
    with job_processing_duration_seconds.labels(job_type="metadata").time():
        try:
            # Fetch the URL and extract basic info
            response = requests.get(
                job["url"], timeout=10, headers={"User-Agent": "URLShortener-Bot/1.0"}
            )

            result = {
                "title": "Page Title",  # Would extract from HTML
                "description": "Page description",
                "status_code": response.status_code,
                "content_type": response.headers.get("content-type", "unknown"),
            }

            save_job_result(job["short_code"], "metadata", "completed", result)
            jobs_processed_total.labels(job_type="metadata", status="completed").inc()
            print(f"Metadata fetched for {job['short_code']}")

        except Exception as e:
            print(f"Error fetching metadata: {e}")
            save_job_result(job["short_code"], "metadata", "failed", {"error": str(e)})
            jobs_processed_total.labels(job_type="metadata", status="failed").inc()


# Job processors map
JOB_PROCESSORS = {
    "qr_code": process_qr_code,
    "screenshot": process_screenshot,
    "metadata": process_metadata,
}


def process_job(job_data: dict) -> None:
    """Process a single job.

    Args:
        job_data: Dictionary containing job data with 'type' key.
    """
    job_type = job_data.get("type")
    processor = JOB_PROCESSORS.get(job_type)

    if processor:
        processor(job_data)
    else:
        print(f"Unknown job type: {job_type}")


def main() -> None:
    """Main worker loop."""
    print(f"Worker started. Concurrency: {WORKER_CONCURRENCY}")
    print(f"Connecting to Redis at {REDIS_HOST}:{REDIS_PORT}")

    # Start Prometheus metrics server on port 8080
    start_http_server(8080)
    print("Prometheus metrics server started on port 8080")

    while True:
        try:
            # Block until job is available (BLPOP with 1 second timeout)
            result = redis_client.blpop("job_queue", timeout=1)

            if result:
                queue_name, job_json = result
                job_data = json.loads(job_json)
                print(f"Processing job: {job_data}")
                process_job(job_data)

        except KeyboardInterrupt:
            print("Worker shutting down...")
            break
        except Exception as e:
            print(f"Error processing job: {e}")
            time.sleep(1)


if __name__ == "__main__":
    main()
