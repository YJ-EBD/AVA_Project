const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const WebSocket = require('ws');
const { randomUUID } = require('crypto');
const config = require('../src/config');

const baseUrl = process.env.AVA_TEST_BASE_URL || 'http://127.0.0.1:8080';
const wsUrl = process.env.AVA_TEST_WS_URL || 'ws://127.0.0.1:8080/ws';
const password = 'ava-chat-duplicate-1234!';
const users = [
  { email: 'node-duplicate-a@ava.local', name: 'Node Duplicate A' },
  { email: 'node-duplicate-b@ava.local', name: 'Node Duplicate B' }
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
  const passwordHash = await bcrypt.hash(password, 4);
  try {
    for (const user of users) {
      const account = await pool.query(
        `
          INSERT INTO user_accounts (id, email, password_hash, display_name, role, enabled, created_at, updated_at)
          VALUES ($1, $2, $3, $4, 'USER', true, now(), now())
          ON CONFLICT (email) DO UPDATE SET
            password_hash = EXCLUDED.password_hash,
            display_name = EXCLUDED.display_name,
            enabled = true,
            updated_at = now()
          RETURNING id
        `,
        [randomUUID(), user.email, passwordHash, user.name]
      );
      user.id = account.rows[0].id;
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
        [randomUUID(), user.id, user.name, user.email]
      );
      await pool.query(
        'UPDATE sessions SET invalidated_at = now() WHERE account_id = $1 AND invalidated_at IS NULL',
        [user.id]
      );
    }
  } finally {
    await pool.end();
  }
}

async function requestJson(path, {
  method = 'GET',
  token = null,
  body = null
} = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    body: body ? JSON.stringify(body) : null
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;
  if (!response.ok) {
    throw new Error(`${method} ${path} failed: ${response.status} ${text}`);
  }
  return payload;
}

function login(email) {
  return requestJson('/api/auth/login', {
    method: 'POST',
    body: {
      email,
      password,
      forceLogin: true,
      rememberMe: true,
      autoLogin: true
    }
  });
}

function connectStomp(token, name) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(wsUrl);
    const received = [];
    const timeout = setTimeout(() => reject(new Error(`${name} CONNECT timeout`)), 8000);
    let resolved = false;
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
        if (parsed.command === 'CONNECTED' && !resolved) {
          resolved = true;
          clearTimeout(timeout);
          resolve(api);
          continue;
        }
        if (parsed.command === 'MESSAGE') {
          const payload = parsed.body ? JSON.parse(parsed.body) : null;
          received.push({
            destination: parsed.headers.destination || '',
            subscription: parsed.headers.subscription || '',
            payload
          });
        }
      }
    });
    socket.on('error', reject);
    const api = {
      socket,
      received,
      subscribe(destination) {
        socket.send(frame('SUBSCRIBE', {
          id: `${name}-${destination}`,
          destination
        }));
      },
      close() {
        socket.close();
      }
    };
  });
}

function countMatches(client, content, destinationPrefix) {
  return client.received.filter((entry) => {
    if (!entry.destination.startsWith(destinationPrefix)) {
      return false;
    }
    const payload = entry.payload;
    if (payload && payload.content === content) {
      return true;
    }
    return payload &&
      payload.type === 'message' &&
      payload.message &&
      payload.message.content === content;
  });
}

async function main() {
  await seedUsers();
  const [loginA, loginB] = await Promise.all([
    login(users[0].email),
    login(users[1].email)
  ]);
  const room = await requestJson('/api/chat/direct-rooms', {
    method: 'POST',
    token: loginA.accessToken,
    body: {
      targetUserId: users[1].id,
      targetEmail: users[1].email,
      targetName: users[1].name
    }
  });

  const [clientA, clientB] = await Promise.all([
    connectStomp(loginA.accessToken, 'A'),
    connectStomp(loginB.accessToken, 'B')
  ]);
  clientA.subscribe(`/topic/rooms/${room.code}`);
  clientA.subscribe('/user/queue/chat-events');
  clientB.subscribe(`/topic/rooms/${room.code}`);
  clientB.subscribe('/user/queue/chat-events');
  await new Promise((resolve) => setTimeout(resolve, 100));

  const content = `duplicate-check ${Date.now()} ${randomUUID()}`;
  const sent = await requestJson(`/api/chat/rooms/${room.code}/messages`, {
    method: 'POST',
    token: loginA.accessToken,
    body: { content, silent: false, spoiler: false, mentions: [] }
  });
  await new Promise((resolve) => setTimeout(resolve, 600));

  const history = await requestJson(`/api/chat/rooms/${room.code}/messages?limit=20`, {
    token: loginA.accessToken
  });
  const historyMatches = history.filter((message) => message.content === content);
  const senderTopic = countMatches(clientA, content, `/topic/rooms/${room.code}`);
  const senderInbox = countMatches(clientA, content, '/user/queue/chat-events');
  const recipientTopic = countMatches(clientB, content, `/topic/rooms/${room.code}`);
  const recipientInbox = countMatches(clientB, content, '/user/queue/chat-events');
  clientA.close();
  clientB.close();

  const result = {
    ok: true,
    roomCode: room.code,
    sentMessageId: sent.id,
    historyMatchCount: historyMatches.length,
    senderTopicCount: senderTopic.length,
    senderInboxCount: senderInbox.length,
    recipientTopicCount: recipientTopic.length,
    recipientInboxCount: recipientInbox.length,
    senderTopicMessageIds: senderTopic.map((entry) => entry.payload.id),
    senderInboxMessageIds: senderInbox.map((entry) => entry.payload.message && entry.payload.message.id),
    recipientTopicMessageIds: recipientTopic.map((entry) => entry.payload.id),
    recipientInboxMessageIds: recipientInbox.map((entry) => entry.payload.message && entry.payload.message.id)
  };

  const countsAreSingle =
    result.historyMatchCount === 1 &&
    result.senderTopicCount === 1 &&
    result.senderInboxCount === 1 &&
    result.recipientTopicCount === 1 &&
    result.recipientInboxCount === 1;
  if (!countsAreSingle) {
    console.error(JSON.stringify(result, null, 2));
    process.exit(1);
  }
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
