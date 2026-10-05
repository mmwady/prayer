FROM python:3.11-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PIP_NO_CACHE_DIR=1
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libgl1 libglib2.0-0 && rm -rf /var/lib/apt/lists/*
RUN useradd --create-home --uid 10001 app
WORKDIR /app
# CPU-only Torch avoids downloading GPU libraries on the small test VPS.
RUN pip install --index-url https://download.pytorch.org/whl/cpu torch==2.5.1
COPY backend/pyproject.toml backend/README.md ./
COPY backend/app ./app
RUN pip install .
COPY backend/models ./models
RUN mkdir -p /app/data && chown app:app /app/data
USER app
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=4 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=4)"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
