const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const { randomUUID } = require('crypto');
const config = require('../src/config');

const baseUrl = process.env.AVA_TEST_BASE_URL || 'http://127.0.0.1:8080';
const iterations = Math.max(1, Number.parseInt(process.env.AVA_AUTH_TEST_ITERATIONS || '1500', 10));
const email = process.env.AVA_AUTH_TEST_EMAIL || 'node-auth-session@ava.local';
const password = process.env.AVA_AUTH_TEST_PASSWORD || 'ava-auth-session-1234!';

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
  const started = performance.now();
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
  return {
    status: response.status,
    ok: response.ok,
    payload,
    durationMs: Math.round(performance.now() - started)
  };
}

async function seedUser() {
  const pool = new Pool(config.postgres);
  const passwordHash = await bcrypt.hash(password, 4);
  try {
    const accountId = randomUUID();
    const account = await pool.query(
      `
        INSERT INTO user_accounts (id, email, password_hash, display_name, role, enabled, created_at, updated_at)
        VALUES ($1, $2, $3, 'Node Auth Session', 'USER', true, now(), now())
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
        VALUES ($1, $2, 'QA', 'ABBA-S', 'Tester', 'Node Auth Session', $3, 'offline', '#7AA06A', '', '#7AA06A')
        ON CONFLICT (account_id) DO UPDATE SET
          company_name = 'ABBA-S',
          nickname = EXCLUDED.nickname,
          contact_email = EXCLUDED.contact_email
      `,
      [randomUUID(), id, email]
    );
    await pool.query(
      'UPDATE sessions SET invalidated_at = now() WHERE account_id = $1 AND invalidated_at IS NULL',
      [id]
    );
  } finally {
    await pool.end();
  }
}

function loginBody(forceLogin = false) {
  return {
    email,
    password,
    rememberMe: true,
    autoLogin: true,
    forceLogin
  };
}

async function login(forceLogin = false) {
  const response = await requestJson('/api/auth/login', {
    method: 'POST',
    body: loginBody(forceLogin)
  });
  assert(response.payload.accessToken, 'Login response did not include accessToken.');
  assert(response.payload.refreshToken, 'Login response did not include refreshToken.');
  return response;
}

async function expectDuplicateLogin() {
  const response = await requestJson('/api/auth/login', {
    method: 'POST',
    body: loginBody(false),
    expectOk: false
  });
  assert(response.status === 409, `Expected duplicate login status 409, received ${response.status}.`);
  assert(response.payload.code === 'DUPLICATE_LOGIN', `Expected DUPLICATE_LOGIN code, received ${response.payload.code}.`);
  assert(response.payload.details?.duplicateLogin === true, 'Expected duplicateLogin detail flag.');
  return response;
}

async function expectSession(accessToken, expectedValid) {
  const response = await requestJson('/api/auth/session', { token: accessToken });
  assert(response.payload.valid === expectedValid, `Expected session valid=${expectedValid}, received ${response.payload.valid}.`);
  return response;
}

async function expectRefreshRejected(refreshToken) {
  const response = await requestJson('/api/auth/refresh', {
    method: 'POST',
    body: { refreshToken },
    expectOk: false
  });
  assert(response.status === 401, `Expected old refresh token status 401, received ${response.status}.`);
  return response;
}

async function logout(accessToken) {
  await requestJson('/api/auth/logout', {
    method: 'POST',
    token: accessToken
  });
}

async function main() {
  await seedUser();

  const latencies = [];
  for (let index = 0; index < iterations; index += 1) {
    const first = await login(false);
    const duplicate = await expectDuplicateLogin();
    const forced = await login(true);
    assert(forced.payload.replacedPreviousLogin === true, 'Forced login did not report replacedPreviousLogin=true.');
    await expectSession(first.payload.accessToken, false);
    await expectRefreshRejected(first.payload.refreshToken);
    await expectSession(forced.payload.accessToken, true);
    await logout(forced.payload.accessToken);

    latencies.push(
      first.durationMs,
      duplicate.durationMs,
      forced.durationMs
    );
  }

  latencies.sort((a, b) => a - b);
  const avgLatencyMs = Math.round(latencies.reduce((sum, value) => sum + value, 0) / latencies.length);
  const p95LatencyMs = latencies[Math.floor(latencies.length * 0.95)] || 0;

  console.log(JSON.stringify({
    ok: true,
    baseUrl,
    email,
    iterations,
    checkedLoginRequests: iterations * 3,
    checkedSessionInvalidations: iterations,
    checkedRefreshRejections: iterations,
    minLatencyMs: latencies[0] || 0,
    maxLatencyMs: latencies[latencies.length - 1] || 0,
    avgLatencyMs,
    p95LatencyMs
  }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
