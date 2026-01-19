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

# Install curl (needed for health checks) and ca-certificates for Node.js download
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js from official binary distribution (architecture-aware)
ARG NODE_VERSION=22.12.0
RUN ARCH=$(dpkg --print-architecture) && \
    case "$ARCH" in \
        amd64) NODE_ARCH="x64" ;; \
        arm64) NODE_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz \
    | tar -xJ -C /usr/local --strip-components=1 \
    && npm --version && node --version

WORKDIR /app

# Create non-root user FIRST (before installing Playwright)
RUN useradd -m -u 1000 appuser

# Create directories with proper ownership
RUN mkdir -p /app/backend/data && chown -R appuser:appuser /app

# Set Playwright browsers path to a location accessible by appuser
ENV PLAYWRIGHT_BROWSERS_PATH=/app/.playwright-browsers

# ============================================
# Backend Setup
# ============================================
COPY --chown=appuser:appuser apps/backend/pyproject.toml /app/backend/
COPY --chown=appuser:appuser apps/backend/app /app/backend/app

WORKDIR /app/backend

# Install Python dependencies
RUN pip install -e .

# Install Playwright system dependencies as root
RUN python -m playwright install-deps chromium

# Switch to appuser for Playwright browser installation
USER appuser

# Install Playwright browsers as appuser (so they're accessible at runtime)
RUN python -m playwright install chromium

# Switch back to root for remaining setup
USER root

# ============================================
# Frontend Setup
# ============================================
WORKDIR /app/frontend

# Copy built frontend from builder stage
COPY --from=frontend-builder --chown=appuser:appuser /app/frontend/.next ./.next
COPY --from=frontend-builder --chown=appuser:appuser /app/frontend/public ./public
COPY --from=frontend-builder --chown=appuser:appuser /app/frontend/package*.json ./
COPY --from=frontend-builder --chown=appuser:appuser /app/frontend/next.config.ts ./

# Install production dependencies only
RUN npm ci --omit=dev && chown -R appuser:appuser node_modules

# ============================================
# Startup Script
# ============================================
COPY --chown=appuser:appuser docker/start.sh /app/start.sh
RUN chmod +x /app/start.sh

# Ensure all files are owned by appuser
RUN chown -R appuser:appuser /app

# Switch to non-root user for security
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
# Increased start-period for Railway's slower startup
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD curl -f http://localhost:${PORT:-3000}/api/v1/health || exit 1

# Start the application
CMD ["/app/start.sh"]
