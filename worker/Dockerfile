# worker/Dockerfile
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

# Install procps for pgrep (needed for liveness probe)
RUN apt-get update && apt-get install -y procps && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy dependency files first for better caching
COPY pyproject.toml .
COPY uv.lock* .

# Resolve and install Python packages from pyproject/uv.lock
RUN /usr/local/bin/uv venv
ENV VIRTUAL_ENV=/app/.venv
ENV PATH="/app/.venv/bin:$PATH"
RUN uv sync

# Copy application code
COPY worker.py .

# Run the worker
CMD ["python", "worker.py"]
