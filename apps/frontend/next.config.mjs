// @ts-check

// Backend URL for rewrites - in production containers, backend runs on localhost:8000
// For external backend deployments, set BACKEND_INTERNAL_URL
const BACKEND_URL = process.env.BACKEND_INTERNAL_URL || 'http://localhost:8000';

/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {},
  async rewrites() {
    return [
      // Proxy API requests to the backend
      {
        source: '/api/v1/:path*',
        destination: `${BACKEND_URL}/api/v1/:path*`,
      },
      // Legacy rewrite (kept for backwards compatibility)
      {
        source: '/api_be/:path*',
        destination: `${BACKEND_URL}/:path*`,
      },
    ];
  },
};

export default nextConfig;
