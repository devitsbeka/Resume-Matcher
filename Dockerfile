# Resume Matcher Docker Image
# Multi-stage build for optimized image size
# Optimized for Railway deployment (single container with both services)

# ============================================
# Stage 1: Build Frontend
# ============================================
FROM node:22-slim AS frontend-builder

WORKDIR /app/frontend

# Copy package files first for better caching
COPY apps/frontend/package*.json ./

# Install dependencies
RUN npm ci

# Copy frontend source
COPY apps/frontend/ ./

# No NEXT_PUBLIC_API_URL needed - we use relative URLs with Next.js rewrites
# The frontend proxies API requests to the backend internally

# Build the frontend
RUN npm run build

# ============================================
# Stage 2: Final Image
# ============================================
FROM python:3.13-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    NODE_ENV=production

# Install curl and Node.js first
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22.x
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ============================================
# Backend Setup
# ============================================
COPY apps/backend/pyproject.toml /app/backend/
COPY apps/backend/app /app/backend/app

WORKDIR /app/backend

# Install Python dependencies
RUN pip install -e .

# Install Playwright and its system dependencies (as root, before switching to appuser)
# This automatically installs the correct dependencies for the current Debian version
RUN python -m playwright install --with-deps chromium

# ============================================
# Frontend Setup
# ============================================
WORKDIR /app/frontend

# Copy built frontend from builder stage
COPY --from=frontend-builder /app/frontend/.next ./.next
COPY --from=frontend-builder /app/frontend/public ./public
COPY --from=frontend-builder /app/frontend/package*.json ./
COPY --from=frontend-builder /app/frontend/next.config.ts ./

# Install production dependencies only
RUN npm ci --omit=dev

# ============================================
# Startup Script
# ============================================
COPY docker/start.sh /app/start.sh
RUN chmod +x /app/start.sh

# ============================================
# Data Directory & Volume
# ============================================
RUN mkdir -p /app/backend/data

# Create a non-root user for security
RUN useradd -m -u 1000 appuser \
    && chown -R appuser:appuser /app

USER appuser

# Expose ports (Railway uses PORT env var, but we expose both for local Docker use)
EXPOSE 3000 8000

# Note: For persistent data on Railway, attach a volume via the Railway dashboard
# pointing to /app/backend/data (Railway doesn't support VOLUME in Dockerfile)

# Set working directory
WORKDIR /app

# Default environment variables for Railway compatibility
# These can be overridden at runtime
ENV PORT=3000 \
    CORS_ORIGINS="*"

# Health check - uses the frontend port (which proxies to backend)
# This works with Railway's single-port model
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:${PORT:-3000}/api/v1/health || exit 1

# Start the application
CMD ["/app/start.sh"]
