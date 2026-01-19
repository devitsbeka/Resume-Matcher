import { NextResponse } from 'next/server';

// Backend URL for internal health check
const BACKEND_URL = process.env.BACKEND_INTERNAL_URL || 'http://localhost:8000';

export async function GET() {
  const health = {
    status: 'ok',
    frontend: 'healthy',
    backend: 'unknown',
    timestamp: new Date().toISOString(),
  };

  // Try to check backend health
  try {
    const backendResponse = await fetch(`${BACKEND_URL}/api/v1/health`, {
      method: 'GET',
      headers: { Accept: 'application/json' },
      // Short timeout for health check
      signal: AbortSignal.timeout(5000),
    });

    if (backendResponse.ok) {
      health.backend = 'healthy';
    } else {
      health.backend = `unhealthy (status: ${backendResponse.status})`;
      health.status = 'degraded';
    }
  } catch (error) {
    // Backend not reachable - still return 200 so Railway knows frontend is up
    // The backend might still be starting
    health.backend = 'unreachable';
    health.status = 'degraded';
    console.warn('Backend health check failed:', error);
  }

  // Always return 200 if frontend is running
  // This allows Railway to mark the deployment as healthy
  // even if backend is still starting
  return NextResponse.json(health, { status: 200 });
}
