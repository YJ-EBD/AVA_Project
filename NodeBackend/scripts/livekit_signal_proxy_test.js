const http = require('http');
const WebSocket = require('ws');
const { WebSocketServer } = require('ws');
const { attachLiveKitSignalProxy, createLiveKitHttpProxy } = require('../src/livekitSignalProxy');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function listen(server, host = '127.0.0.1') {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, host, () => resolve(server.address().port));
  });
}

function closeServer(server) {
  return new Promise((resolve) => server.close(resolve));
}

async function main() {
  let observedUrl = '';
  const upstream = new WebSocketServer({ noServer: true });
  const upstreamHttp = http.createServer((request, response) => {
    if (request.url === '/rtc/validate?access_token=http-token') {
      response.setHeader('content-type', 'application/json');
      response.end(JSON.stringify({ ok: true, proxiedUrl: request.url }));
      return;
    }
    response.statusCode = 404;
    response.end('not found');
  });
  upstreamHttp.on('upgrade', (request, socket, head) => {
    upstream.handleUpgrade(request, socket, head, (ws) => {
      upstream.emit('connection', ws, request);
    });
  });
  upstream.on('connection', (ws, request) => {
    observedUrl = request.url || '';
    ws.send(`auth:${request.headers.authorization || ''}`);
    ws.on('message', (data, isBinary) => {
      ws.send(data, { binary: isBinary });
    });
  });
  const upstreamPort = await listen(upstreamHttp);

  const liveKitHttpProxy = createLiveKitHttpProxy({
    enabled: true,
    upstreamUrl: `ws://127.0.0.1:${upstreamPort}`
  });
  const proxyHttp = http.createServer((req, res) => {
    liveKitHttpProxy(req, res, () => {
      res.statusCode = 404;
      res.end('not found');
    });
  });
  attachLiveKitSignalProxy(proxyHttp, {
    enabled: true,
    upstreamUrl: `ws://127.0.0.1:${upstreamPort}`
  });
  const proxyPort = await listen(proxyHttp);

  const echoed = await new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://127.0.0.1:${proxyPort}/rtc?access_token=test-token`, {
      headers: { Authorization: 'Bearer websocket-token' }
    });
    const timeout = setTimeout(() => reject(new Error('Timed out waiting for proxy echo.')), 5000);
    let sawAuth = false;
    ws.on('open', () => ws.send('azoom-proxy-ok'));
    ws.on('message', (data) => {
      const text = data.toString('utf8');
      if (text === 'auth:Bearer websocket-token') {
        sawAuth = true;
        return;
      }
      clearTimeout(timeout);
      resolve({ text, sawAuth });
      ws.close();
    });
    ws.on('error', reject);
  });

  assert(echoed.text === 'azoom-proxy-ok', 'Proxy did not echo through upstream LiveKit server.');
  assert(echoed.sawAuth, 'Proxy did not forward Authorization header to upstream WebSocket.');
  assert(
    observedUrl === '/rtc?access_token=test-token',
    `Proxy did not preserve LiveKit request path/query: ${observedUrl}`
  );

  const httpResponse = await fetch(`http://127.0.0.1:${proxyPort}/rtc/validate?access_token=http-token`);
  const httpPayload = await httpResponse.json();
  assert(httpResponse.ok, `HTTP proxy returned ${httpResponse.status}.`);
  assert(httpPayload.proxiedUrl === '/rtc/validate?access_token=http-token', 'HTTP validate proxy did not preserve URL.');

  await closeServer(proxyHttp);
  upstream.close();
  await closeServer(upstreamHttp);
  console.log(JSON.stringify({ ok: true, observedUrl, httpProxy: true }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
