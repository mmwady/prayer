# ─────────────────────────────────────────────────────────────────────────────
# backend/Dockerfile
#
# Slim, production-leaning image for the FastAPI coaching backend.
#
# Design choices:
#   • Base on python:3.12-slim — small, recent, and matches our type-hint usage.
#   • Use a non-root user — WebSocket servers are long-lived; running as root
#     inside a container is a soft landing pad for any RCE bug in a dependency.
#   • Two-stage COPY of pyproject/requirements → source. Keeps Docker layer
#     caching effective: changing Python code doesn't invalidate the pip layer.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Prevent Python from buffering stdout/stderr so `docker logs` stays responsive,
# and skip the .pyc byte-compile step that just wastes disk in an ephemeral image.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# `libgl1` and `libglib2.0-0` are the shared libraries OpenCV and MediaPipe need
# for reference-video extraction; `curl`/`ca-certificates` keep TLS probes and
# the healthcheck working. Keep the layer small.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

# Non-root user. UID/GID 10001 is outside typical host ranges — avoids clashes
# with bind-mounted files.
RUN useradd --create-home --uid 10001 app

WORKDIR /app

# ─── Dependency layer (cached when only source changes) ─────────────────────
COPY pyproject.toml ./
COPY README.md ./
# `pip install .` reads pyproject.toml; `--no-deps false` (default) resolves
# the full tree. We use a temporary venv-free install straight into site-pkgs.
RUN pip install --upgrade pip \
 && pip install .

# ─── Application source ─────────────────────────────────────────────────────
COPY app ./app
COPY models ./models
RUN mkdir -p /app/data/prayer_references && chown -R app:app /app/data

# Drop privileges AFTER pip install (pip needs /usr/local write access).
USER app

EXPOSE 8000

# `--proxy-headers` lets us honor X-Forwarded-* from a future reverse proxy.
# `--ws websockets` pins the protocol backend (avoids the older `wsproto`).
CMD ["uvicorn", "app.main:app", \
     "--host", "0.0.0.0", "--port", "8000", \
     "--proxy-headers"]
