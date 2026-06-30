const { URL } = require('url');
const http = require('http');
const https = require('https');
const { WebSocket, WebSocketServer } = require('ws');
const config = require('./config');

function isLiveKitSignalPath(url) {
  try {
    const parsed = new URL(url || '/', 'http://localhost');
    return parsed.pathname === '/rtc' || parsed.pathname.startsWith('/rtc/');
  } catch {
    return false;
  }
}

function upstreamUrlForRequest(requestUrl, upstreamBaseUrl) {
  const base = new URL(upstreamBaseUrl);
  const incoming = new URL(requestUrl || '/', 'http://localhost');
  base.pathname = incoming.pathname;
  base.search = incoming.search;
  return base.toString();
}

function httpUpstreamUrlForRequest(requestUrl, upstreamBaseUrl) {
  const upstream = new URL(upstreamUrlForRequest(requestUrl, upstreamBaseUrl));
  upstream.protocol = upstream.protocol === 'wss:' ? 'https:' : 'http:';
  return upstream;
}

function closeQuietly(socket, code = 1011, reason = 'LiveKit proxy closed') {
  try {
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.close(code, reason);
    } else if (socket && socket.readyState === WebSocket.CONNECTING) {
      socket.terminate();
    }
  } catch {
    // Ignore cleanup races while proxying WebSocket shutdown.
  }
}

function createLiveKitHttpProxy(options = {}) {
  const enabled = options.enabled ?? config.livekit.signalProxyEnabled;
  const upstreamBaseUrl = options.upstreamUrl ?? config.livekit.signalProxyUpstreamUrl;
  return (req, res, next) => {
    const requestUrl = req.originalUrl || req.url || '/';
    if (!isLiveKitSignalPath(requestUrl)) {
      next();
      return;
    }
    if (!enabled || !upstreamBaseUrl) {
      res.status(503).json({ status: 503, code: 'LIVEKIT_PROXY_DISABLED' });
      return;
    }

    const upstream = httpUpstreamUrlForRequest(requestUrl, upstreamBaseUrl);
    const headers = {
      ...req.headers,
      host: upstream.host,
      'x-forwarded-for': req.socket.remoteAddress || '',
      'x-forwarded-proto': req.protocol || 'http',
      'x-forwarded-host': req.headers.host || ''
    };
    delete headers.connection;
    delete headers['content-length'];

    const proxyRequest = (upstream.protocol === 'https:' ? https : http).request(
      upstream,
      {
        method: req.method,
        headers
      },
      (proxyResponse) => {
        res.statusCode = proxyResponse.statusCode || 502;
        for (const [key, value] of Object.entries(proxyResponse.headers)) {
          if (value != null) {
            res.setHeader(key, value);
          }
        }
        proxyResponse.pipe(res);
      }
    );
    proxyRequest.on('error', () => {
      if (!res.headersSent) {
        res.status(502).json({ status: 502, code: 'LIVEKIT_PROXY_UPSTREAM_ERROR' });
      } else {
        res.end();
      }
    });
    req.pipe(proxyRequest);
  };
}

function attachLiveKitSignalProxy(httpServer, options = {}) {
  const enabled = options.enabled ?? config.livekit.signalProxyEnabled;
  const upstreamBaseUrl = options.upstreamUrl ?? config.livekit.signalProxyUpstreamUrl;
  const wss = new WebSocketServer({ noServer: true });

  wss.on('connection', (clientSocket, request) => {
    const pending = [];
    let upstreamOpen = false;
    const upstreamUrl = upstreamUrlForRequest(request.url, upstreamBaseUrl);
    const upstreamHost = new URL(upstreamUrl).host;
    const protocols = String(request.headers['sec-websocket-protocol'] || '')
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean);
    const upstreamSocket = new WebSocket(
      upstreamUrl,
      protocols.length > 0 ? protocols : undefined,
      {
        headers: {
          ...(request.headers.authorization ? { authorization: request.headers.authorization } : {}),
          ...(request.headers.cookie ? { cookie: request.headers.cookie } : {}),
          ...(request.headers.origin ? { origin: request.headers.origin } : {}),
          ...(request.headers['user-agent'] ? { 'user-agent': request.headers['user-agent'] } : {}),
          host: upstreamHost,
          'x-forwarded-for': request.socket.remoteAddress || '',
          'x-forwarded-proto': request.socket.encrypted ? 'wss' : 'ws',
          'x-forwarded-host': request.headers.host || ''
        }
      }
    );

    clientSocket.on('message', (data, isBinary) => {
      if (!upstreamOpen) {
        pending.push({ data, isBinary });
        return;
      }
      upstreamSocket.send(data, { binary: isBinary });
    });
    clientSocket.on('close', () => closeQuietly(upstreamSocket, 1000, 'client closed'));
    clientSocket.on('error', () => closeQuietly(upstreamSocket));

    upstreamSocket.on('open', () => {
      upstreamOpen = true;
      while (pending.length > 0 && upstreamSocket.readyState === WebSocket.OPEN) {
        const item = pending.shift();
        upstreamSocket.send(item.data, { binary: item.isBinary });
      }
    });
    upstreamSocket.on('message', (data, isBinary) => {
      if (clientSocket.readyState === WebSocket.OPEN) {
        clientSocket.send(data, { binary: isBinary });
      }
    });
    upstreamSocket.on('unexpected-response', () => {
      closeQuietly(clientSocket);
    });
    upstreamSocket.on('close', (code, reason) => closeQuietly(clientSocket, code, reason.toString()));
    upstreamSocket.on('error', () => {
      closeQuietly(clientSocket);
    });
  });

  httpServer.on('upgrade', (request, socket, head) => {
    if (!isLiveKitSignalPath(request.url)) {
      return;
    }
    if (!enabled || !upstreamBaseUrl) {
      socket.destroy();
      return;
    }
    wss.handleUpgrade(request, socket, head, (clientSocket) => {
      wss.emit('connection', clientSocket, request);
    });
  });

  return wss;
}

module.exports = {
  attachLiveKitSignalProxy,
  createLiveKitHttpProxy,
  isLiveKitSignalPath,
  httpUpstreamUrlForRequest,
  upstreamUrlForRequest
};
