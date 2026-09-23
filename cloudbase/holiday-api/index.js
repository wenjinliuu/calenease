const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const DATA = path.join(__dirname, 'holidays', 'v1');

function respond(req, res) {
  const pathname = new URL(req.url || '/', 'http://localhost').pathname;
  const match = /^\/holidays\/v1\/(index|20\d{2})\.json$/.exec(pathname);
  if (req.method === 'OPTIONS') {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS', 'Cache-Control': 'no-store' });
    res.end();
    return;
  }
  if (!['GET', 'HEAD'].includes(req.method) || !match) {
    res.writeHead(match ? 405 : 404, { 'Content-Type': 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ error: match ? 'method_not_allowed' : 'not_found' }));
    return;
  }
  const filename = `${match[1]}.json`;
  try {
    const body = fs.readFileSync(path.join(DATA, filename));
    res.writeHead(200, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'Access-Control-Allow-Origin': '*',
      'X-Content-Type-Options': 'nosniff',
      'Content-Length': body.length,
    });
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch (error) {
    if (error.code !== 'ENOENT') console.error('holiday read error:', error);
    res.writeHead(error.code === 'ENOENT' ? 404 : 500, { 'Content-Type': 'application/json; charset=utf-8', 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ error: error.code === 'ENOENT' ? 'not_found' : 'internal_error' }));
  }
}

if (require.main === module) {
  http.createServer(respond).listen(Number(process.env.PORT || 9000), '0.0.0.0');
}

module.exports = { respond };
