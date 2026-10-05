"""Never cache account responses and bound JSON before parsing."""

from starlette.responses import JSONResponse


class AccountBoundary:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or not scope["path"].startswith("/api/v1/accounts"):
            await self.app(scope, receive, send)
            return
        body, size = [], 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            size += len(message.get("body", b""))
            if size > 16384:
                await JSONResponse(
                    {"detail": "ACCOUNT_REQUEST_TOO_LARGE"},
                    status_code=413,
                    headers={"Cache-Control": "no-store"},
                )(scope, receive, send)
                return
            body.append(message)
            if not message.get("more_body", False):
                break

        async def replay():
            if body:
                return body.pop(0)
            return await receive()

        async def no_cache(message):
            if message["type"] == "http.response.start":
                message["headers"] = [
                    (k, v) for k, v in message["headers"] if k.lower() != b"cache-control"
                ] + [(b"cache-control", b"no-store")]
            await send(message)

        await self.app(scope, replay, no_cache)
