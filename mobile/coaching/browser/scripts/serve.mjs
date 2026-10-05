import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
export function serve(root, port = 8780) {
  const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.wasm': 'application/wasm', '.onnx': 'application/octet-stream', '.task': 'application/octet-stream', '.png': 'image/png', '.jpg': 'image/jpeg', '.ttf': 'font/ttf' };
  const server = http.createServer(async (req, res) => {
    try {
      if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405); res.end(); return; }
      const url = new URL(req.url, 'http://localhost'), file = path.resolve(root, '.' + decodeURIComponent(url.pathname));
      if (!file.startsWith(path.resolve(root) + path.sep) && file !== path.resolve(root)) throw Error('Invalid path');
      const final = (await stat(file)).isDirectory() ? path.join(file, 'index.html') : file;
      const bytes = await readFile(final), ext = path.extname(final);
      res.writeHead(200, { 'Content-Type': mime[ext] ?? 'application/octet-stream', 'Cache-Control': url.searchParams.has('v') ? 'public, max-age=31536000, immutable' : 'no-cache', 'X-Content-Type-Options': 'nosniff' });
      res.end(req.method === 'HEAD' ? undefined : bytes);
    } catch { res.writeHead(404); res.end('Not found'); }
  });
  return new Promise(resolve => server.listen(port, '127.0.0.1', () => resolve(server)));
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = path.resolve(process.argv[2] ?? fileURLToPath(new URL('../../web', import.meta.url)));
  const port = Number(process.argv[3] ?? 8780);
  await serve(root, port); console.log(`Static files: http://127.0.0.1:${port}/recognizer/`);
}
