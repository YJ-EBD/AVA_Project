const express = require('express');
const { randomUUID } = require('crypto');
const { query } = require('../db');
const { asyncHandler, forbidden, notFound } = require('../errors');
const { authRequired } = require('../services/authService');
const { normalizeCompany } = require('../services/profileService');

const router = express.Router();
router.use(authRequired);

function requireAdmin(req) {
  if (req.principal.role !== 'ADMIN' && req.principal.role !== 'SUPERUSER') {
    throw forbidden('Admin permission is required.');
  }
}

function adminUser(row) {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    role: row.role,
    enabled: Boolean(row.enabled),
    companyName: normalizeCompany(row.company_name),
    department: row.department || '',
    position: row.position || '',
    status: row.status || '',
    createdAt: row.created_at
  };
}

async function userById(userId) {
  const result = await query(
    `
      SELECT a.id, a.email, a.display_name, a.role, a.enabled, a.created_at,
             p.company_name, p.department, p.position, p.status
      FROM user_accounts a
      LEFT JOIN user_profiles p ON p.account_id = a.id
      WHERE a.id = $1
    `,
    [userId]
  );
  return result.rows[0] || null;
}

async function audit(req, action, resourceType, resourceId, metadata = {}) {
  await query(
    `
      INSERT INTO audit_logs (
        id, actor_account_id, actor_email, action, resource_type, resource_id,
        ip_address, user_agent, metadata, created_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
    `,
    [
      randomUUID(),
      req.principal.userId,
      req.principal.email,
      action,
      resourceType,
      resourceId || '',
      req.ip || '',
      req.get('user-agent') || '',
      JSON.stringify(metadata)
    ]
  );
}

router.get('/overview', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const result = await query(`
    SELECT
      (SELECT COUNT(*)::int FROM user_accounts) AS total_users,
      (SELECT COUNT(*)::int FROM user_accounts WHERE enabled = true) AS enabled_users,
      (SELECT COUNT(*)::int FROM user_accounts WHERE enabled = false) AS disabled_users,
      (SELECT COUNT(*)::int FROM chat_rooms) AS chat_rooms,
      (SELECT COUNT(*)::int FROM chat_message_records) AS chat_messages,
      (SELECT COUNT(*)::int FROM notifications WHERE read_at IS NULL) AS unread_notifications
  `);
  const row = result.rows[0] || {};
  res.json({
    totalUsers: Number(row.total_users || 0),
    enabledUsers: Number(row.enabled_users || 0),
    disabledUsers: Number(row.disabled_users || 0),
    chatRooms: Number(row.chat_rooms || 0),
    chatMessages: Number(row.chat_messages || 0),
    unreadNotifications: Number(row.unread_notifications || 0)
  });
}));

router.get('/users', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const result = await query(
    `
      SELECT a.id, a.email, a.display_name, a.role, a.enabled, a.created_at,
             p.company_name, p.department, p.position, p.status
      FROM user_accounts a
      LEFT JOIN user_profiles p ON p.account_id = a.id
      ORDER BY a.created_at DESC
      LIMIT 500
    `
  );
  res.json(result.rows.map(adminUser));
}));

router.get('/users/pending-approvals', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const result = await query(
    `
      SELECT a.id, a.email, a.display_name, a.role, a.enabled, a.created_at,
             p.company_name, p.department, p.position, p.status
      FROM user_accounts a
      LEFT JOIN user_profiles p ON p.account_id = a.id
      WHERE a.enabled = false
      ORDER BY a.created_at DESC
      LIMIT 500
    `
  );
  res.json(result.rows.map(adminUser));
}));

router.post('/users/:userId/approve', asyncHandler(async (req, res) => {
  requireAdmin(req);
  await query('UPDATE user_accounts SET enabled = true, updated_at = now() WHERE id = $1', [req.params.userId]);
  const row = await userById(req.params.userId);
  if (!row) {
    throw notFound('User not found.');
  }
  await audit(req, 'APPROVE_USER', 'USER', req.params.userId);
  res.json(adminUser(row));
}));

router.put('/users/:userId', asyncHandler(async (req, res) => {
  requireAdmin(req);
  await query(
    `
      UPDATE user_accounts
      SET display_name = COALESCE($2, display_name),
          role = COALESCE($3, role),
          enabled = COALESCE($4, enabled),
          updated_at = now()
      WHERE id = $1
    `,
    [
      req.params.userId,
      req.body.displayName || null,
      req.body.role || null,
      typeof req.body.enabled === 'boolean' ? req.body.enabled : null
    ]
  );
  await query(
    `
      UPDATE user_profiles
      SET company_name = COALESCE($2, company_name),
          department = COALESCE($3, department),
          position = COALESCE($4, position)
      WHERE account_id = $1
    `,
    [
      req.params.userId,
      req.body.companyName || null,
      req.body.department || null,
      req.body.position || null
    ]
  );
  const row = await userById(req.params.userId);
  if (!row) {
    throw notFound('User not found.');
  }
  await audit(req, 'UPDATE_USER', 'USER', req.params.userId, req.body);
  res.json(adminUser(row));
}));

router.get('/settings', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const result = await query('SELECT * FROM app_settings ORDER BY setting_key ASC');
  res.json(result.rows.map((row) => ({
    key: row.setting_key,
    value: row.setting_value,
    description: row.description || '',
    updatedAt: row.updated_at
  })));
}));

router.put('/settings', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const key = String(req.body.key || '').trim();
  const value = String(req.body.value || '');
  const description = String(req.body.description || '');
  const result = await query(
    `
      INSERT INTO app_settings (
        setting_key, setting_value, description, updated_by_account_id, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, now(), now())
      ON CONFLICT (setting_key)
      DO UPDATE SET
        setting_value = EXCLUDED.setting_value,
        description = EXCLUDED.description,
        updated_by_account_id = EXCLUDED.updated_by_account_id,
        updated_at = now()
      RETURNING *
    `,
    [key, value, description, req.principal.userId]
  );
  await audit(req, 'UPSERT_SETTING', 'SETTING', key);
  const row = result.rows[0];
  res.json({
    key: row.setting_key,
    value: row.setting_value,
    description: row.description || '',
    updatedAt: row.updated_at
  });
}));

router.get('/audit-logs', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const result = await query('SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT 200');
  res.json(result.rows.map((row) => ({
    action: row.action,
    actorEmail: row.actor_email || '',
    resourceType: row.resource_type,
    resourceId: row.resource_id || '',
    metadata: row.metadata || '',
    createdAt: row.created_at
  })));
}));

router.get('/system-logs', asyncHandler(async (req, res) => {
  requireAdmin(req);
  const result = await query('SELECT * FROM system_logs ORDER BY created_at DESC LIMIT 200');
  res.json(result.rows.map((row) => ({
    requestId: row.request_id,
    accountEmail: row.account_email || '',
    method: row.method,
    path: row.path,
    queryString: row.query_string || '',
    status: Number(row.status || 0),
    durationMs: Number(row.duration_ms || 0),
    ipAddress: row.ip_address || '',
    errorMessage: row.error_message || '',
    createdAt: row.created_at
  })));
}));

module.exports = router;
