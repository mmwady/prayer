"""Tunnel-only forwarding app; keeps local operator routes off the public URL."""
from app.main import app as backend_app


async def app(scope, receive, send):
    path = scope.get('path', '')
    allowed = (path == '/healthz' or path == '/api/v1/prayer-reference'
               or path == '/api/v1/prayer-guidance'
               or path == '/api/v1/prayer-analyses'
               or path.startswith('/api/v1/prayer-analyses/')
               or path == '/api/v1/mosque-demo'
               or path == '/api/v1/accounts'
               or path.startswith('/api/v1/accounts/')
               or path.startswith('/api/v1/mosque-demo/'))
    if scope['type'] == 'http' and not allowed:
        await send({'type': 'http.response.start', 'status': 404,
                    'headers': [(b'content-type', b'application/json')]})
        await send({'type': 'http.response.body', 'body': b'{"detail":"Not Found"}'})
        return
    if scope['type'] == 'websocket' and not allowed:
        await send({'type': 'websocket.close', 'code': 1008})
        return
    await backend_app(scope, receive, send)
