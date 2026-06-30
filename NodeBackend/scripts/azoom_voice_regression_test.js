const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const { randomUUID } = require('crypto');
const config = require('../src/config');

const baseUrl = process.env.AVA_TEST_BASE_URL || 'http://127.0.0.1:8080';
const iterations = Math.max(1, Number.parseInt(process.env.AVA_AZOOM_TEST_ITERATIONS || '1500', 10));
const email = process.env.AVA_AZOOM_TEST_EMAIL || 'azoom-regression-a@ava.local';
const password = process.env.AVA_AZOOM_TEST_PASSWORD || 'ava-azoom-regression-1234!';

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function requestJson(path, { method = 'GET', token = null, body = null, expectOk = true } = {}) {
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
  return { status: response.status, payload };
}

async function seedUser() {
  const pool = new Pool(config.postgres);
  const passwordHash = await bcrypt.hash(password, 4);
  try {
    const accountId = randomUUID();
    const account = await pool.query(
      `
        INSERT INTO user_accounts (id, email, password_hash, display_name, role, enabled, created_at, updated_at)
        VALUES ($1, $2, $3, 'AZOOM Regression A', 'USER', true, now(), now())
        ON CONFLICT (email) DO UPDATE SET
          password_hash = EXCLUDED.password_hash,
          display_name = EXCLUDED.display_name,
          enabled = true,
          updated_at = now()
        RETURNING id
      `,
      [accountId, email, passwordHash]
    );
    const id = account.rows[0].id;
    await pool.query(
      `
        INSERT INTO user_profiles (
          id, account_id, department, company_name, position, nickname,
          contact_email, status, avatar_color, status_message, profile_background_color
        )
        VALUES ($1, $2, 'QA', 'ABBA-S', 'Tester', 'AZOOM Regression A', $3, 'offline', '#7AA06A', '', '#7AA06A')
        ON CONFLICT (account_id) DO UPDATE SET
          company_name = 'ABBA-S',
          department = 'QA',
          nickname = EXCLUDED.nickname,
          contact_email = EXCLUDED.contact_email
      `,
      [randomUUID(), id, email]
    );
    await pool.query('DELETE FROM azoom_voice_participants WHERE account_id = $1', [id]);
    await pool.query('UPDATE sessions SET invalidated_at = now() WHERE account_id = $1 AND invalidated_at IS NULL', [id]);
    return id;
  } finally {
    await pool.end();
  }
}

async function makeStale(channelId, accountId) {
  const pool = new Pool(config.postgres);
  try {
    await pool.query(
      `
        UPDATE azoom_voice_participants
        SET updated_at = now() - interval '10 minutes'
        WHERE channel_id = $1 AND account_id = $2
      `,
      [channelId, accountId]
    );
  } finally {
    await pool.end();
  }
}

function participantFor(channel, targetEmail) {
  return (channel.participants || []).find(
    (participant) => String(participant.email).toLowerCase() === targetEmail.toLowerCase()
  );
}

async function main() {
  const accountId = await seedUser();
  const login = await requestJson('/api/auth/login', {
    method: 'POST',
    body: { email, password, rememberMe: true, autoLogin: true, forceLogin: true }
  });
  const token = login.payload.accessToken;
  assert(token, 'Login did not return accessToken.');

  let testChannelId = '';
  try {
    const created = await requestJson('/api/azoom/voice-channels', {
      method: 'POST',
      token,
      body: { name: `AZOOM Regression ${Date.now()}` }
    });
    testChannelId = created.payload.id;
    assert(testChannelId, 'AZOOM channel create did not return id.');

    for (let index = 0; index < iterations; index += 1) {
      const join = await requestJson(`/api/azoom/voice-channels/${testChannelId}/join`, {
        method: 'POST',
        token
      });
      assert(join.payload.liveKit.enabled === true, 'LiveKit token was not enabled.');
      assert(join.payload.liveKit.token, 'LiveKit token was empty.');
      assert(participantFor(join.payload.channel, email), 'Joined participant was missing.');

      const muted = index % 2 === 0;
      const status = await requestJson(`/api/azoom/voice-channels/${testChannelId}/status`, {
        method: 'PUT',
        token,
        body: { muted, deafened: false, cameraEnabled: false, screenSharing: false }
      });
      const participant = participantFor(status.payload, email);
      assert(participant, 'Status response participant was missing.');
      assert(participant.muted === muted, 'Muted status did not round-trip.');

      const left = await requestJson(`/api/azoom/voice-channels/${testChannelId}/leave`, {
        method: 'POST',
        token
      });
      assert(!participantFor(left.payload, email), 'Participant remained after leave.');
    }

    await requestJson(`/api/azoom/voice-channels/${testChannelId}/join`, { method: 'POST', token });
    await makeStale(testChannelId, accountId);
    const channels = await requestJson('/api/azoom/channels', { token });
    const testChannel = channels.payload.voiceChannels.find((channel) => channel.id === testChannelId);
    assert(testChannel, 'Test channel was missing from channel list.');
    assert(!participantFor(testChannel, email), 'Stale participant was not cleaned up.');
    assert(testChannel.startedAt == null, 'Empty stale channel should not remain started.');

    console.log(JSON.stringify({
      ok: true,
      baseUrl,
      iterations,
      checkedJoinStatusLeaveCycles: iterations,
      staleCleanupChecked: true
    }, null, 2));
  } finally {
    if (testChannelId) {
      await requestJson(`/api/azoom/voice-channels/${testChannelId}/leave`, {
        method: 'POST',
        token,
        expectOk: false
      }).catch(() => {});
      await requestJson(`/api/azoom/channels/${testChannelId}`, {
        method: 'DELETE',
        token,
        expectOk: false
      }).catch(() => {});
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
