const assert = require('node:assert/strict');
const { test } = require('node:test');
const http = require('node:http');
const { respond } = require('./index');

test('public contract and missing paths', async () => {
  const server = http.createServer(respond).listen(0);
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const index = await fetch(`${base}/holidays/v1/index.json`);
    assert.equal(index.status, 200);
    assert.equal(index.headers.get('content-type'), 'application/json; charset=utf-8');
    assert.equal(index.headers.get('cache-control'), 'max-age=3600');
    assert.equal(index.headers.get('access-control-allow-origin'), '*');
    assert.equal((await index.json()).schemaVersion, 1);
    const year = await fetch(`${base}/holidays/v1/2026.json`);
    assert.equal(year.headers.get('cache-control'), 'max-age=86400');
    assert.equal((await year.json()).year, 2026);
    assert.equal((await fetch(`${base}/holidays/v1/2030.json`)).status, 404);
  } finally {
    server.close();
  }
});
