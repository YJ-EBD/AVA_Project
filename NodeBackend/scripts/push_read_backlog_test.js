const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const { randomUUID } = require('crypto');
const config = require('../src/config');

const baseUrl = process.env.AVA_TEST_BASE_URL || 'http://127.0.0.1:8080';
const password = 'ava-push-read-1234!';
const users = [
  { email: 'node-push-read-a@ava.local', name: 'Node Push Read A' },
  { email: 'node-push-read-b@ava.local', name: 'Node Push Read B' }
];

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function requestJson(path, {
  method = 'GET',
  body = null,
  token = null,
  expectOk = true
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
  if (expectOk && !response.ok) {
    throw new Error(`${method} ${path} failed: ${response.status} ${text}`);
  }
  return payload;
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

function login(email) {
  return requestJson('/api/auth/login', {
    method: 'POST',
    body: { email, password, forceLogin: true }
  });
}

async function main() {
  await seedUsers();
  const [sender, recipient] = await Promise.all([
    login(users[0].email),
    login(users[1].email)
  ]);

  const room = await requestJson('/api/chat/direct-rooms', {
    method: 'POST',
    token: sender.accessToken,
    body: { targetUserId: users[1].id, targetEmail: users[1].email }
  });
  const content = `push-read-${Date.now()}`;
  const sent = await requestJson(`/api/chat/rooms/${room.code}/messages`, {
    method: 'POST',
    token: sender.accessToken,
    body: { content, silent: false, spoiler: false, mentions: [] }
  });

  await requestJson(`/api/chat/rooms/${room.code}/read`, {
    method: 'POST',
    token: recipient.accessToken
  });

  const pool = new Pool(config.postgres);
  try {
    const pushEvents = await pool.query(
      `
        SELECT id, type, source_id
        FROM mobile_push_events
        WHERE account_id = $1 AND source_id = $2
      `,
      [users[1].id, sent.id]
    );
    assert(pushEvents.rowCount === 1, `Expected one push event, found ${pushEvents.rowCount}.`);
    assert(
      pushEvents.rows[0].type === 'chat_message',
      `Expected chat_message push type, received ${pushEvents.rows[0].type}.`
    );
  } finally {
    await pool.end();
  }

  const events = await requestJson('/api/push/events?limit=100', {
    token: recipient.accessToken
  });
  const matchingEvents = events.filter((event) => event.sourceId === sent.id);
  assert(
    matchingEvents.length === 0,
    `Read chat push event was returned in backlog ${matchingEvents.length} time(s).`
  );

  console.log(JSON.stringify({
    ok: true,
    roomCode: room.code,
    messageId: sent.id,
    returnedMatchingPushEvents: matchingEvents.length
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
