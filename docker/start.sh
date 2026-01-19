#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Railway/Cloud platform compatibility
# Railway sets PORT env var for the public-facing port
FRONTEND_PORT="${PORT:-3000}"
BACKEND_PORT="8000"

# Print banner
print_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'

 ██████╗ ███████╗███████╗██╗   ██╗███╗   ███╗███████╗
 ██╔══██╗██╔════╝██╔════╝██║   ██║████╗ ████║██╔════╝
 ██████╔╝█████╗  ███████╗██║   ██║██╔████╔██║█████╗
 ██╔══██╗██╔══╝  ╚════██║██║   ██║██║╚██╔╝██║██╔══╝
 ██║  ██║███████╗███████║╚██████╔╝██║ ╚═╝ ██║███████╗
 ╚═╝  ╚═╝╚══════╝╚══════╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝

 ███╗   ███╗ █████╗ ████████╗ ██████╗██╗  ██╗███████╗██████╗
 ████╗ ████║██╔══██╗╚══██╔══╝██╔════╝██║  ██║██╔════╝██╔══██╗
 ██╔████╔██║███████║   ██║   ██║     ███████║█████╗  ██████╔╝
 ██║╚██╔╝██║██╔══██║   ██║   ██║     ██╔══██║██╔══╝  ██╔══██╗
 ██║ ╚═╝ ██║██║  ██║   ██║   ╚██████╗██║  ██║███████╗██║  ██║
 ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝    ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝

EOF
    echo -e "${NC}"
    echo -e "${BOLD}        Crazy Stuff with Resumes and Cover letters${NC}"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Print status message
status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

# Print info message
info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Print warning message
warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Print error message
error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Cleanup function for graceful shutdown
cleanup() {
    echo ""
    info "Shutting down Resume Matcher..."

    # Kill backend if running
    if [ -n "$BACKEND_PID" ] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        kill "$BACKEND_PID" 2>/dev/null || true
        wait "$BACKEND_PID" 2>/dev/null || true
    fi

    status "Shutdown complete"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# Print banner
print_banner

# Display port configuration
info "Port configuration:"
echo -e "  Frontend port: ${FRONTEND_PORT} (public)"
echo -e "  Backend port:  ${BACKEND_PORT} (internal)"
echo ""

# Check and create data directory
info "Checking data directory..."
DATA_DIR="/app/backend/data"
if [ ! -d "$DATA_DIR" ]; then
    mkdir -p "$DATA_DIR"
    status "Created data directory: $DATA_DIR"
else
    status "Data directory exists: $DATA_DIR"
fi

# Check for Playwright browsers
info "Checking Playwright browsers..."
# PLAYWRIGHT_BROWSERS_PATH is set in Dockerfile to /app/.playwright-browsers
PLAYWRIGHT_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/app/.playwright-browsers}"
if [ -d "$PLAYWRIGHT_PATH" ] && [ "$(ls -A $PLAYWRIGHT_PATH 2>/dev/null)" ]; then
    status "Playwright browsers found at $PLAYWRIGHT_PATH"
else
    warn "Installing Playwright Chromium (this may take a moment)..."
    cd /app/backend && python -m playwright install chromium 2>&1 || {
        warn "Playwright installation had warnings (this is usually OK)"
    }
    status "Playwright setup complete"
fi

# Start backend on internal port
echo ""
info "Starting backend server on port ${BACKEND_PORT}..."
cd /app/backend
python -m uvicorn app.main:app --host 0.0.0.0 --port ${BACKEND_PORT} &
BACKEND_PID=$!

# Wait for backend to be ready
info "Waiting for backend to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:${BACKEND_PORT}/api/v1/health > /dev/null 2>&1; then
        status "Backend is ready (PID: $BACKEND_PID)"
        break
    fi
    if [ $i -eq 30 ]; then
        error "Backend failed to start within 30 seconds"
        exit 1
    fi
    sleep 1
done

# Start frontend on the public port (Railway's PORT or default 3000)
echo ""
info "Starting frontend server on port ${FRONTEND_PORT}..."
cd /app/frontend

# Verify frontend build exists
if [ ! -d ".next" ]; then
    error "Frontend build not found! Missing .next directory"
    exit 1
fi
status "Frontend build verified"

# Next.js uses the PORT env var automatically when running `next start`
# We set it explicitly here for clarity
info "Running: PORT=${FRONTEND_PORT} npm start"
PORT=${FRONTEND_PORT} npm start &
FRONTEND_PID=$!

# Wait a moment for frontend to initialize
sleep 3

# Check if frontend process is still running
if ! kill -0 "$FRONTEND_PID" 2>/dev/null; then
    error "Frontend failed to start!"
    exit 1
fi

# Wait for frontend to be ready (via the proxied health endpoint)
echo ""
info "Waiting for frontend to be ready..."
for i in {1..60}; do
    if curl -s http://localhost:${FRONTEND_PORT}/api/v1/health > /dev/null 2>&1; then
        status "Frontend is ready and proxying to backend (PID: $FRONTEND_PID)"
        break
    fi
    if [ $i -eq 60 ]; then
        warn "Frontend health check timed out after 60 seconds"
        warn "Continuing anyway - Railway health check will retry"
    fi
    sleep 1
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
status "Resume Matcher is running!"
echo ""
echo -e "  ${BOLD}Frontend:${NC}  http://localhost:${FRONTEND_PORT}"
echo -e "  ${BOLD}Backend:${NC}   http://localhost:${BACKEND_PORT} (internal)"
echo -e "  ${BOLD}API Docs:${NC}  http://localhost:${FRONTEND_PORT}/api/v1/docs (proxied)"
echo ""
if [ -n "$RAILWAY_STATIC_URL" ]; then
    echo -e "  ${BOLD}Railway URL:${NC} ${RAILWAY_STATIC_URL}"
    echo ""
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
info "Application ready for health checks"
echo ""

# Wait for processes
wait $FRONTEND_PID
