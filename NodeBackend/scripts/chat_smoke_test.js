const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const WebSocket = require('ws');
const { randomUUID } = require('crypto');
const config = require('../src/config');

const baseUrl = process.env.AVA_TEST_BASE_URL || 'http://127.0.0.1:8080';
const wsUrl = process.env.AVA_TEST_WS_URL || 'ws://127.0.0.1:8080/ws';
const messageCount = Math.max(1, Number.parseInt(process.env.AVA_TEST_MESSAGES || '1', 10));
const password = 'ava-test-1234!';
const users = [
  { email: 'node-realtime-a@ava.local', name: 'Node Realtime A' },
  { email: 'node-realtime-b@ava.local', name: 'Node Realtime B' }
];

function frame(command, headers = {}, body = '') {
  const lines = [command];
  for (const [key, value] of Object.entries(headers)) {
    if (value != null) {
      lines.push(`${key}:${value}`);
    }
  }
  return `${lines.join('\n')}\n\n${body}\0`;
}

function parseFrame(raw) {
  const text = raw.toString('utf8').replace(/\0+$/, '');
  const firstLine = text.indexOf('\n');
  const command = text.slice(0, firstLine).trim();
  const headerEnd = text.indexOf('\n\n');
  const headerBlock = headerEnd >= 0 ? text.slice(firstLine + 1, headerEnd) : '';
  const body = headerEnd >= 0 ? text.slice(headerEnd + 2) : '';
  const headers = {};
  for (const line of headerBlock.split('\n')) {
    const separator = line.indexOf(':');
    if (separator > 0) {
      headers[line.slice(0, separator)] = line.slice(separator + 1);
    }
  }
  return { command, headers, body };
}

async function seedUsers() {
  const pool = new Pool(config.postgres);
  const passwordHash = await bcrypt.hash(password, 10);
  try {
    for (const user of users) {
      const accountId = randomUUID();
      const account = await pool.query(
        `
          INSERT INTO user_accounts (id, email, password_hash, display_name, role, enabled, created_at, updated_at)
          VALUES ($1, $2, $3, $4, 'USER', true, now(), now())
          ON CONFLICT (email) DO UPDATE SET
            password_hash = EXCLUDED.password_hash,
            display_name = EXCLUDED.display_name,
            enabled = true,
            updated_at = now()
          RETURNING id, email, display_name
        `,
        [accountId, user.email, passwordHash, user.name]
      );
      const id = account.rows[0].id;
      await pool.query(
        `
          INSERT INTO user_profiles (
            id, account_id, department, company_name, position, nickname,
            contact_email, status, avatar_color, status_message, profile_background_color
          )
          VALUES ($1, $2, 'QA', 'ABBA-S', 'Tester', $3, $4, 'offline', '#7AA06A', '', '#7AA06A')
          ON CONFLICT (account_id) DO UPDATE SET
            company_name = 'ABBA-S',
            nickname = EXCLUDED.nickname,
            contact_email = EXCLUDED.contact_email
        `,
        [randomUUID(), id, user.name, user.email]
      );
      user.id = id;
    }
  } finally {
    await pool.end();
  }
}

async function postJson(path, body, token = null) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    body: JSON.stringify(body)
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;
  if (!response.ok) {
    throw new Error(`${path} failed: ${response.status} ${text}`);
  }
  return payload;
}

async function login(email) {
  return postJson('/api/auth/login', {
    email,
    password,
    forceLogin: true,
    rememberMe: true,
    autoLogin: true
  });
}

function connectStomp(token, name) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl);
    const received = [];
    const pending = [];
    const timeout = setTimeout(() => reject(new Error(`${name} CONNECT timeout`)), 5000);
    socket.on('open', () => {
      socket.send(frame('CONNECT', {
        'accept-version': '1.2',
        Authorization: `Bearer ${token}`
      }));
    });
    socket.on('message', (data) => {
      for (const chunk of data.toString('utf8').split('\0')) {
        if (!chunk.trim()) {
          continue;
        }
        const parsed = parseFrame(`${chunk}\0`);
        if (parsed.command === 'CONNECTED') {
          clearTimeout(timeout);
          resolve(api);
          continue;
        }
        if (parsed.command === 'MESSAGE') {
          const payload = parsed.body ? JSON.parse(parsed.body) : null;
          received.push(payload);
          for (let index = pending.length - 1; index >= 0; index -= 1) {
            const waiter = pending[index];
            if (waiter.predicate(payload)) {
              pending.splice(index, 1);
              clearTimeout(waiter.timer);
              waiter.done(payload);
            }
          }
        }
      }
    });
    socket.on('error', reject);
    const api = {
      socket,
      received,
      subscribe(destination) {
        socket.send(frame('SUBSCRIBE', {
          id: `${name}-${destination}-${Math.random()}`,
          destination
        }));
      },
      send(destination, payload) {
        socket.send(frame('SEND', {
          destination,
          Authorization: `Bearer ${token}`,
          'content-type': 'application/json'
        }, JSON.stringify(payload)));
      },
      waitFor(predicate, timeoutMs = 5000) {
        const existing = received.find(predicate);
        if (existing) {
          return Promise.resolve(existing);
        }
        return new Promise((done, fail) => {
          const timer = setTimeout(() => fail(new Error(`${name} wait timeout`)), timeoutMs);
          pending.push({ predicate, timer, done });
        });
      },
      close() {
        socket.close();
      }
    };
  });
}

async function main() {
  await seedUsers();
  const loginA = await login(users[0].email);
  const loginB = await login(users[1].email);
  const room = await postJson('/api/chat/direct-rooms', {
    targetUserId: users[1].id,
    targetEmail: users[1].email,
    targetName: users[1].name
  }, loginA.accessToken);

  const clientA = await connectStomp(loginA.accessToken, 'A');
  const clientB = await connectStomp(loginB.accessToken, 'B');
  clientA.subscribe(`/topic/rooms/${room.code}`);
  clientB.subscribe(`/topic/rooms/${room.code}`);
  clientA.subscribe('/user/queue/chat-events');
  clientB.subscribe('/user/queue/chat-events');
  await new Promise((resolve) => setTimeout(resolve, 50));

  const latencies = [];
  let lastTopicMessage = null;
  let lastUserEvent = null;
  for (let index = 0; index < messageCount; index += 1) {
    const started = Date.now();
    const content = `node smoke ${started} ${index + 1}/${messageCount}`;
    clientA.send(`/app/rooms/${room.code}/send`, { content, silent: false, spoiler: false, mentions: [] });
    const [topicMessage, userEvent] = await Promise.all([
      clientB.waitFor((payload) => payload && payload.content === content, 5000),
      clientB.waitFor((payload) => payload && payload.type === 'message' && payload.message && payload.message.content === content, 5000)
    ]);
    lastTopicMessage = topicMessage;
    lastUserEvent = userEvent;
    latencies.push(Date.now() - started);
  }

  clientA.close();
  clientB.close();
  console.log(JSON.stringify({
    ok: true,
    roomCode: room.code,
    messageCount,
    messageId: lastTopicMessage.id,
    unreadCount: lastTopicMessage.unreadCount,
    recipientUnreadCount: lastUserEvent.room.unreadCount,
    minLatencyMs: Math.min(...latencies),
    maxLatencyMs: Math.max(...latencies),
    avgLatencyMs: Math.round(latencies.reduce((sum, value) => sum + value, 0) / latencies.length)
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
