const http = require('http');
const fs = require('fs');
const path = require('path');

const host = '0.0.0.0';
const port = Number(process.env.PORT || 8080);
const root = path.join(__dirname, 'build', 'web');

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
};

function cacheControlFor(filePath) {
  const fileName = path.basename(filePath).toLowerCase();
  const ext = path.extname(filePath).toLowerCase();
  const mustRevalidate = new Set([
    'index.html',
    'flutter_bootstrap.js',
    'flutter.js',
    'flutter_service_worker.js',
    'main.dart.js',
    'version.json',
    'manifest.json',
  ]);

  if (mustRevalidate.has(fileName) || ext === '.html') {
    return 'no-store, no-cache, must-revalidate, proxy-revalidate';
  }

  if (ext === '.js' || ext === '.json') {
    return 'no-cache, must-revalidate';
  }

  return 'public, max-age=86400';
}

function safeFilePath(requestUrl) {
  const urlPath = decodeURIComponent((requestUrl || '/').split('?')[0]);
  const normalizedPath = path.normalize(urlPath).replace(/^(\.\.[/\\])+/, '');
  const filePath = path.join(root, normalizedPath === '/' ? 'index.html' : normalizedPath);
  return filePath.startsWith(root) ? filePath : path.join(root, 'index.html');
}

const server = http.createServer((req, res) => {
  let filePath = safeFilePath(req.url);

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(root, 'index.html');
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Erro ao carregar o app.');
      return;
    }

    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, {
      'Content-Type': mimeTypes[ext] || 'application/octet-stream',
      'Cache-Control': cacheControlFor(filePath),
    });
    res.end(data);
  });
});

server.listen(port, host, () => {
  console.log(`Frontend listening on http://${host}:${port}`);
});
