"""Transport limits before JSON parsing; admin defaults to loopback access only."""
import hmac
import json


class AnalysisBoundary:
    def __init__(self, app, settings):
        self.app, self.settings = app, settings

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        path = scope.get('path', '')
        headers = dict(scope['headers'])
        original_send = send

        async def private_send(message):
            if message['type'] == 'http.response.start':
                message = {**message, 'headers': [
                    (key, value) for key, value in message.get('headers', [])
                    if key.lower() != b'cache-control'] + [(b'cache-control', b'no-store')]}
            await original_send(message)

        if path.startswith('/api/v1/prayer-analyses'):
            send = private_send
        if path.startswith('/admin'):
            token = self.settings.prayer_admin_token
            local = (scope.get('client') or ('',))[0] in ('127.0.0.1', '::1', 'testclient')
            supplied = headers.get(b'authorization', b'').decode('latin1')
            if (token and not hmac.compare_digest(supplied.encode(), ('Bearer ' + token).encode())) or (not token and not local):
                return await self.reject(send, 403, 'ADMIN_ACCESS_RESTRICTED')
        if path.startswith('/api/v1/prayer-analyses') and scope['method'] == 'POST':
            limit = self.settings.analysis_max_request_bytes
            chunks, size = [], 0
            while True:
                message = await receive()
                if message['type'] == 'http.disconnect':
                    return
                chunk = message.get('body', b'')
                size += len(chunk)
                if size > limit:
                    return await self.reject(send, 413, 'REQUEST_TOO_LARGE')
                chunks.append(chunk)
                if not message.get('more_body', False):
                    break
            sent = False

            async def replay():
                nonlocal sent
                if not sent:
                    sent = True
                    return {'type': 'http.request', 'body': b''.join(chunks), 'more_body': False}
                return await receive()

            return await self.app(scope, replay, send)
        return await self.app(scope, receive, send)

    @staticmethod
    async def reject(send, status, detail):
        body = json.dumps({'detail': detail}).encode()
        await send({'type': 'http.response.start', 'status': status,
                    'headers': [(b'content-type', b'application/json')]})
        await send({'type': 'http.response.body', 'body': body})
