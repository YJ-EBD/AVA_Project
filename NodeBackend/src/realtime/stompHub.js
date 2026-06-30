const { WebSocketServer } = require('ws');
const { parseToken } = require('../jwt');
const { isCurrentSession, principalFromClaims } = require('../services/authService');

function parseFrame(raw) {
  const text = raw.toString('utf8').replace(/\0+$/, '');
  const firstLineEnd = text.indexOf('\n');
  if (firstLineEnd < 0) {
    return null;
  }
  const command = text.slice(0, firstLineEnd).trim();
  const headerEnd = text.indexOf('\n\n', firstLineEnd + 1);
  const headerBlock = headerEnd >= 0 ? text.slice(firstLineEnd + 1, headerEnd) : text.slice(firstLineEnd + 1);
  const body = headerEnd >= 0 ? text.slice(headerEnd + 2) : '';
  const headers = {};
  for (const line of headerBlock.split('\n')) {
    if (!line.trim()) {
      continue;
    }
    const separator = line.indexOf(':');
    if (separator < 0) {
      continue;
    }
    headers[line.slice(0, separator)] = line.slice(separator + 1);
  }
  return { command, headers, body };
}

function frame(command, headers = {}, body = '') {
  const lines = [command];
  for (const [key, value] of Object.entries(headers)) {
    if (value != null) {
      lines.push(`${key}:${value}`);
    }
  }
  return `${lines.join('\n')}\n\n${body}\0`;
}

function jsonFrameBody(payload) {
  return JSON.stringify(payload == null ? null : payload);
}

class StompHub {
  constructor() {
    this.clients = new Set();
    this.chatService = null;
  }

  setChatService(chatService) {
    this.chatService = chatService;
  }

  attach(httpServer) {
    this.wss = new WebSocketServer({ server: httpServer, path: '/ws' });
    this.wss.on('connection', (socket) => this.handleConnection(socket));
  }

  handleConnection(socket) {
    const client = {
      socket,
      principal: null,
      subscriptions: new Map()
    };
    this.clients.add(client);
    socket.on('message', (data) => this.handleMessage(client, data));
    socket.on('close', () => this.clients.delete(client));
    socket.on('error', () => this.clients.delete(client));
  }

  async handleMessage(client, data) {
    const raw = data.toString('utf8');
    if (raw === '\n' || raw.trim() === '') {
      return;
    }
    for (const chunk of raw.split('\0')) {
      if (!chunk.trim()) {
        continue;
      }
      const parsed = parseFrame(`${chunk}\0`);
      if (!parsed) {
        continue;
      }
      try {
        await this.dispatchFrame(client, parsed);
      } catch (error) {
        this.sendError(client, error.message || 'WebSocket error.');
      }
    }
  }

  async dispatchFrame(client, parsed) {
    switch (parsed.command) {
      case 'CONNECT':
      case 'STOMP':
        await this.connect(client, parsed.headers);
        break;
      case 'SUBSCRIBE':
        this.subscribe(client, parsed.headers);
        break;
      case 'UNSUBSCRIBE':
        this.unsubscribe(client, parsed.headers);
        break;
      case 'SEND':
        await this.send(client, parsed.headers, parsed.body);
        break;
      case 'DISCONNECT':
        client.socket.close();
        break;
      default:
        break;
    }
  }

  async connect(client, headers) {
    const authorization = headers.Authorization || headers.authorization || '';
    if (authorization.startsWith('Bearer ')) {
      const claims = parseToken(authorization.slice(7));
      if (claims && claims.type === 'access' && await isCurrentSession(claims.userId, claims.sessionId)) {
        client.principal = principalFromClaims(claims);
      }
    }
    client.socket.send(frame('CONNECTED', {
      version: '1.2',
      'heart-beat': '10000,10000'
    }));
  }

  subscribe(client, headers) {
    const id = headers.id || headers.subscription || `${Date.now()}-${Math.random()}`;
    const destination = headers.destination;
    if (!destination) {
      return;
    }
    client.subscriptions.set(id, destination);
  }

  unsubscribe(client, headers) {
    const id = headers.id || headers.subscription;
    if (id) {
      client.subscriptions.delete(id);
    }
  }

  async send(client, headers, body) {
    if (!this.chatService) {
      throw new Error('Chat service is not ready.');
    }
    const authorization = headers.Authorization || headers.authorization || '';
    let principal = client.principal;
    if (!principal && authorization.startsWith('Bearer ')) {
      const claims = parseToken(authorization.slice(7));
      if (claims && claims.type === 'access' && await isCurrentSession(claims.userId, claims.sessionId)) {
        principal = principalFromClaims(claims);
        client.principal = principal;
      }
    }
    if (!principal) {
      throw new Error('WebSocket authentication is required.');
    }

    const destination = headers.destination || '';
    const sendMatch = destination.match(/^\/app\/rooms\/([^/]+)\/send$/);
    const typingMatch = destination.match(/^\/app\/rooms\/([^/]+)\/typing$/);
    const payload = body ? JSON.parse(body) : {};
    if (sendMatch) {
      await this.chatService.sendMessage(sendMatch[1], payload, principal);
      return;
    }
    if (typingMatch) {
      await this.chatService.publishTyping(typingMatch[1], payload, principal);
    }
  }

  publish(destination, payload) {
    const body = jsonFrameBody(payload);
    for (const client of this.clients) {
      for (const [subscriptionId, subscribedDestination] of client.subscriptions.entries()) {
        if (subscribedDestination === destination && client.socket.readyState === 1) {
          client.socket.send(frame('MESSAGE', {
            subscription: subscriptionId,
            destination,
            'content-type': 'application/json'
          }, body));
        }
      }
    }
  }

  sendToUser(email, destinationSuffix, payload) {
    if (!email) {
      return;
    }
    const normalizedEmail = String(email).toLowerCase();
    const candidates = new Set([
      `/user${destinationSuffix}`,
      destinationSuffix
    ]);
    const body = jsonFrameBody(payload);
    for (const client of this.clients) {
      if (!client.principal || String(client.principal.email).toLowerCase() !== normalizedEmail) {
        continue;
      }
      for (const [subscriptionId, subscribedDestination] of client.subscriptions.entries()) {
        if (candidates.has(subscribedDestination) && client.socket.readyState === 1) {
          client.socket.send(frame('MESSAGE', {
            subscription: subscriptionId,
            destination: subscribedDestination,
            'content-type': 'application/json'
          }, body));
        }
      }
    }
  }

  sendError(client, message) {
    if (client.socket.readyState === 1) {
      client.socket.send(frame('ERROR', { message }, JSON.stringify({ message })));
    }
  }
}

module.exports = {
  StompHub
};
