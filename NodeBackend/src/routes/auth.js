const express = require('express');
const bcrypt = require('bcryptjs');
const { randomUUID, randomInt, createHash } = require('crypto');
const { query } = require('../db');
const { asyncHandler, badRequest } = require('../errors');
const { authenticateBearer, authRequired, login, refresh, logout, verifyPassword, findAccount } = require('../services/authService');
const { accountByEmail, accountWithProfile, toProfileResponse } = require('../services/profileService');

function maskEmail(email) {
  const [name, domain] = String(email || '').split('@');
  if (!name || !domain) {
    return '';
  }
  const visible = name.slice(0, Math.min(3, name.length));
  return `${visible}${'*'.repeat(Math.max(1, name.length - visible.length))}@${domain}`;
}

function codeHash(email, code) {
  return createHash('sha256').update(`${String(email).toLowerCase()}:${code}`).digest('hex');
}

function createAuthRouter(realtimeHub) {
  const router = express.Router();

  router.post('/email-verifications', asyncHandler(async (req, res) => {
    const email = String(req.body.email || '').trim().toLowerCase();
    if (!email) {
      throw badRequest('Email is required.');
    }
    const code = String(randomInt(100000, 999999));
    await query(
      `
        INSERT INTO auth_email_verification_codes (
          id, email, code_hash, created_at, expires_at, attempts
        )
        VALUES ($1, $2, $3, now(), now() + interval '5 minutes', 0)
      `,
      [randomUUID(), email, codeHash(email, code)]
    );
    console.log(`[AVA] Email verification code for ${email}: ${code}`);
    res.json({ email, expiresInSeconds: 300 });
  }));

  router.post('/email-verifications/confirm', asyncHandler(async (req, res) => {
    const email = String(req.body.email || '').trim().toLowerCase();
    const code = String(req.body.code || req.body.emailVerificationCode || '').trim();
    const result = await query(
      `
        UPDATE auth_email_verification_codes
        SET verified_at = now(), attempts = attempts + 1
        WHERE id = (
          SELECT id
          FROM auth_email_verification_codes
          WHERE email = $1
            AND code_hash = $2
            AND consumed_at IS NULL
            AND expires_at > now()
          ORDER BY created_at DESC
          LIMIT 1
        )
        RETURNING email
      `,
      [email, codeHash(email, code)]
    );
    res.json({ email, verified: result.rowCount > 0 });
  }));

  router.post('/signup', asyncHandler(async (req, res) => {
    const email = String(req.body.email || '').trim().toLowerCase();
    const password = String(req.body.password || '');
    const displayName = String(req.body.displayName || '').trim();
    if (!email || !password || !displayName) {
      throw badRequest('Email, password and displayName are required.');
    }
    const existing = await accountByEmail(email);
    if (existing) {
      throw badRequest('Account already exists.');
    }
    const verification = await query(
      `
        UPDATE auth_email_verification_codes
        SET consumed_at = now()
        WHERE id = (
          SELECT id
          FROM auth_email_verification_codes
          WHERE email = $1 AND verified_at IS NOT NULL AND consumed_at IS NULL
          ORDER BY verified_at DESC
          LIMIT 1
        )
        RETURNING id
      `,
      [email]
    );
    if (verification.rowCount === 0 && process.env.AVA_SIGNUP_REQUIRE_EMAIL_VERIFICATION !== 'false') {
      throw badRequest('Email verification is required.');
    }
    const accountId = randomUUID();
    const passwordHash = await bcrypt.hash(password, 10);
    await query(
      `
        INSERT INTO user_accounts (id, email, password_hash, display_name, role, enabled, created_at, updated_at)
        VALUES ($1, $2, $3, $4, 'USER', false, now(), now())
      `,
      [accountId, email, passwordHash, displayName]
    );
    await query(
      `
        INSERT INTO user_profiles (
          id, account_id, department, company_name, position, nickname, phone_number,
          contact_email, gender, birth_date, status, avatar_color, status_message,
          profile_background_color
        )
        VALUES ($1, $2, $3, $4, 'Staff', $5, $6, $7, $8, $9, 'offline', '#7AA06A', '', '#7AA06A')
      `,
      [
        randomUUID(),
        accountId,
        req.body.department || 'Unknown',
        req.body.companyName || 'ABBA-S',
        req.body.nickname || displayName,
        req.body.phoneNumber || null,
        req.body.contactEmail || email,
        req.body.gender || null,
        req.body.birthDate || null
      ]
    );
    const account = await accountWithProfile(accountId);
    res.json({
      user: toProfileResponse(account),
      pendingApproval: true,
      message: 'Account created and pending approval.'
    });
  }));

  router.post('/login', asyncHandler(async (req, res) => {
    res.json(await login(req.body, realtimeHub));
  }));

  router.post('/refresh', asyncHandler(async (req, res) => {
    res.json(await refresh(req.body.refreshToken));
  }));

  router.post('/logout', authRequired, asyncHandler(async (req, res) => {
    await logout(req.principal);
    res.json({ status: 'logged_out' });
  }));

  router.get('/session', asyncHandler(async (req, res) => {
    const principal = await authenticateBearer(req, { optional: true });
    res.json({ valid: Boolean(principal) });
  }));

  router.post('/verify-password', authRequired, asyncHandler(async (req, res) => {
    await verifyPassword(req.principal, req.body.password);
    res.json({ status: 'verified' });
  }));

  router.get('/find-account', asyncHandler(async (req, res) => {
    const found = await findAccount(req.query.email);
    res.json({
      found: Boolean(found.exists),
      maskedEmail: found.exists ? maskEmail(found.email) : ''
    });
  }));

  return router;
}

module.exports = {
  createAuthRouter
};
