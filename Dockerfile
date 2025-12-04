# Stage 1: Build the Application
FROM python:3.11-slim AS build

# Prevent Python from writing .pyc files and enable unbuffered stdout/stderr
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /usr/src/app

# Install system deps needed for building certain Python packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Create a virtual environment for isolated installs
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy the entire project into the build stage. This avoids failing when a single file copy (requirements.txt) is missing.
COPY . .

# Install Python deps if requirements.txt exists.
# If you prefer pyproject/poetry, add logic here to handle that.
RUN pip install --upgrade pip setuptools wheel && \
    if [ -f requirements.txt ]; then \
      pip install --no-cache-dir -r requirements.txt; \
    else \
      echo "requirements.txt not found — skipping pip install"; \
    fi

# Collect static files (Django). If your project needs specific env vars for collectstatic,
# set them via build args or adjust this command accordingly.
RUN if [ -f manage.py ]; then python manage.py collectstatic --noinput || echo "collectstatic skipped or failed"; fi

# Stage 2: Final runtime image
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /usr/src/app

# Install only runtime system libs (keep image small)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy virtualenv and application from build stage
COPY --from=build /opt/venv /opt/venv
COPY --from=build /usr/src/app /usr/src/app

ENV PATH="/opt/venv/bin:$PATH"

# Create a non-root user and fix permissions
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /usr/src/app
USER appuser

# Default port configuration (can be overridden by Fly.toml / env)
ENV PORT=8080
EXPOSE $PORT

# Run migrations then start Daphne (ASGI). Use sh -c to allow multi-command.
# Replace `myproject.asgi:application` with your actual asgi import path.
CMD ["sh", "-c", "python manage.py migrate --noinput && daphne -b 0.0.0.0 -p $PORT myproject.asgi:application"]
