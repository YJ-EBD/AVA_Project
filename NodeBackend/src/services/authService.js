const bcrypt = require('bcryptjs');
const { randomUUID } = require('crypto');
const config = require('../config');
const { one, query, tx } = require('../db');
const { badRequest, conflict, forbidden, unauthorized } = require('../errors');
const { issueTokens, parseToken } = require('../jwt');
const { accountByEmail, accountWithProfile, toProfileResponse, OFFLINE } = require('./profileService');

function principalFromClaims(claims) {
  if (!claims) {
    return null;
  }
  return {
    userId: claims.userId,
    email: claims.email,
    displayName: claims.displayName,
    role: claims.role,
    sessionId: claims.sessionId
  };
}

async function isCurrentSession(userId, sessionId, client = null) {
  if (!userId || !sessionId) {
    return false;
  }
  const executor = client || { query };
  const result = await executor.query(
    `
      UPDATE sessions
      SET last_seen_at = now()
      WHERE account_id = $1
        AND session_id = $2
        AND invalidated_at IS NULL
        AND expires_at > now()
      RETURNING session_id
    `,
    [userId, sessionId]
  );
  return result.rowCount > 0;
}

async function authenticateBearer(req, { optional = false } = {}) {
  const authorization = req.get('Authorization') || req.get('authorization') || '';
  if (!authorization.startsWith('Bearer ')) {
    if (optional) {
      return null;
    }
    throw unauthorized();
  }
  const claims = parseToken(authorization.slice(7));
  if (!claims || claims.type !== 'access') {
    if (optional) {
      return null;
    }
    throw unauthorized('Invalid or expired access token.');
  }
  const active = await isCurrentSession(claims.userId, claims.sessionId);
  if (!active) {
    if (optional) {
      return null;
    }
    throw unauthorized('Login session is no longer active.');
  }
  return principalFromClaims(claims);
}

function authRequired(req, res, next) {
  authenticateBearer(req)
    .then((principal) => {
      req.principal = principal;
      next();
    })
    .catch(next);
}

async function login(request, realtimeHub = null) {
  const email = String(request.email || '').trim().toLowerCase();
  const password = String(request.password || '');
  if (!email || !password) {
    throw badRequest('Email and password are required.');
  }

  const account = await accountByEmail(email);
  if (!account || !(await bcrypt.compare(password, account.password_hash))) {
    throw unauthorized('Invalid email or password.');
  }
  if (!account.enabled) {
    throw forbidden('Account is pending approval.');
  }

  const remember = Boolean(request.rememberMe || request.autoLogin);
  const activeSession = await one(
    `
      SELECT session_id
      FROM sessions
      WHERE account_id = $1 AND invalidated_at IS NULL AND expires_at > now()
      ORDER BY last_seen_at DESC
      LIMIT 1
    `,
    [account.id]
  );
  if (activeSession && !request.forceLogin) {
    throw conflict('Another active login session exists.', { duplicateLogin: true });
  }

  const sessionId = randomUUID();
  const sessionDays = remember ? config.sessionRememberDays : config.sessionHours / 24;
  const expiresAt = new Date(Date.now() + sessionDays * 24 * 60 * 60 * 1000);
  const replacedPreviousLogin = Boolean(activeSession);

  await tx(async (client) => {
    if (activeSession) {
      await client.query(
        'UPDATE sessions SET invalidated_at = now() WHERE account_id = $1 AND invalidated_at IS NULL',
        [account.id]
      );
    }
    await client.query(
      `
        INSERT INTO sessions (id, account_id, session_id, remember_login, expires_at, created_at, last_seen_at)
        VALUES ($1, $2, $3, $4, $5, now(), now())
      `,
      [randomUUID(), account.id, sessionId, remember, expiresAt]
    );
  });

  if (realtimeHub && activeSession) {
    realtimeHub.sendToUser(account.email, '/queue/auth-events', {
      type: 'forced-logout',
      reason: 'DUPLICATE_LOGIN',
      at: new Date().toISOString()
    });
  }

  const fullAccount = await accountWithProfile(account.id);
  return {
    ...issueTokens(account, sessionId),
    replacedPreviousLogin,
    user: toProfileResponse(fullAccount)
  };
}

async function refresh(refreshToken) {
  const claims = parseToken(refreshToken);
  if (!claims || claims.type !== 'refresh') {
    throw unauthorized('Invalid or expired refresh token.');
  }
  if (!(await isCurrentSession(claims.userId, claims.sessionId))) {
    throw unauthorized('Login session is no longer active.');
  }
  const account = await accountWithProfile(claims.userId);
  if (!account || !account.enabled) {
    throw unauthorized('Account is not available.');
  }
  return {
    ...issueTokens(account, claims.sessionId),
    replacedPreviousLogin: false,
    user: toProfileResponse(account)
  };
}

async function logout(principal) {
  if (!principal) {
    return;
  }
  await tx(async (client) => {
    await client.query(
      'UPDATE sessions SET invalidated_at = now() WHERE account_id = $1 AND session_id = $2 AND invalidated_at IS NULL',
      [principal.userId, principal.sessionId]
    );
    await client.query(
      'UPDATE user_profiles SET status = $2, presence_updated_at = now() WHERE account_id = $1',
      [principal.userId, OFFLINE]
    );
  });
}

async function verifyPassword(principal, password) {
  const account = await accountWithProfile(principal.userId);
  if (!account || !(await bcrypt.compare(String(password || ''), account.password_hash))) {
    throw unauthorized('Password verification failed.');
  }
}

async function findAccount(email) {
  const account = await accountByEmail(String(email || '').trim());
  return {
    exists: Boolean(account),
    email: account ? account.email : String(email || '').trim(),
    displayName: account ? account.display_name : null,
    enabled: account ? Boolean(account.enabled) : false
  };
}

module.exports = {
  authenticateBearer,
  authRequired,
  isCurrentSession,
  principalFromClaims,
  login,
  refresh,
  logout,
  verifyPassword,
  findAccount
};
