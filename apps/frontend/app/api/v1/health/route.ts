// Minimal health check - just returns 200 if Next.js is running
// No external dependencies, no imports that could fail

export async function GET() {
  return new Response(
    JSON.stringify({
      status: 'ok',
      timestamp: new Date().toISOString(),
    }),
    {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
      },
    }
  );
}
