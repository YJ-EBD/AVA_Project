const express = require('express');
const { query } = require('../db');
const { asyncHandler, notFound } = require('../errors');
const { authRequired } = require('../services/authService');
const {
  accountWithProfile,
  effectiveCompany,
  profilesForPrincipal,
  toProfileResponse,
  ONLINE,
  BACKGROUND,
  OFFLINE
} = require('../services/profileService');

const router = express.Router();
router.use(authRequired);

router.get('/me', asyncHandler(async (req, res) => {
  const account = await accountWithProfile(req.principal.userId);
  if (!account) {
    throw notFound('Account not found.');
  }
  res.json(toProfileResponse(account));
}));

router.put('/me/presence', asyncHandler(async (req, res) => {
  const requested = String(req.body.status || '').trim().toLowerCase();
  const status = requested === 'online' || req.body.status === ONLINE
    ? ONLINE
    : requested === 'background' || requested === 'away' || req.body.status === BACKGROUND
      ? BACKGROUND
      : OFFLINE;
  await query(
    'UPDATE user_profiles SET status = $2, presence_updated_at = now() WHERE account_id = $1',
    [req.principal.userId, status]
  );
  const account = await accountWithProfile(req.principal.userId);
  res.json(toProfileResponse(account));
}));

router.put('/me/profile', asyncHandler(async (req, res) => {
  await query(
    `
      UPDATE user_profiles
      SET department = COALESCE($2, department),
          position = COALESCE($3, position),
          nickname = COALESCE($4, nickname),
          phone_number = COALESCE($5, phone_number),
          contact_email = COALESCE($6, contact_email),
          gender = COALESCE($7, gender),
          birth_date = COALESCE($8, birth_date),
          status_message = COALESCE($9, status_message),
          avatar_image_url = COALESCE($10, avatar_image_url),
          profile_background_color = COALESCE($11, profile_background_color),
          profile_background_image_url = COALESCE($12, profile_background_image_url)
      WHERE account_id = $1
    `,
    [
      req.principal.userId,
      req.body.department || null,
      req.body.position || null,
      req.body.nickname || null,
      req.body.phoneNumber || null,
      req.body.contactEmail || null,
      req.body.gender || null,
      req.body.birthDate || null,
      req.body.statusMessage || null,
      req.body.avatarImageUrl || null,
      req.body.profileBackgroundColor || null,
      req.body.profileBackgroundImageUrl || null
    ]
  );
  const account = await accountWithProfile(req.principal.userId);
  res.json(toProfileResponse(account));
}));

router.get('/me/chat-folders', asyncHandler(async (req, res) => {
  const result = await query('SELECT folders_json FROM user_chat_folder_settings WHERE account_id = $1', [req.principal.userId]);
  res.json(JSON.parse(result.rows[0] && result.rows[0].folders_json || '[]'));
}));

router.put('/me/chat-folders', asyncHandler(async (req, res) => {
  const folders = Array.isArray(req.body.folders) ? req.body.folders : [];
  await query(
    `
      INSERT INTO user_chat_folder_settings (account_id, folders_json, filter_order_json, quiet_room_ids_json, pinned_room_ids_json, updated_at)
      VALUES ($1, $2, '[]', '[]', '[]', now())
      ON CONFLICT (account_id) DO UPDATE SET folders_json = EXCLUDED.folders_json, updated_at = now()
    `,
    [req.principal.userId, JSON.stringify(folders)]
  );
  res.json(folders);
}));

router.get('/me/chat-folder-order', asyncHandler(async (req, res) => {
  const result = await query('SELECT filter_order_json FROM user_chat_folder_settings WHERE account_id = $1', [req.principal.userId]);
  res.json(JSON.parse(result.rows[0] && result.rows[0].filter_order_json || '[]'));
}));

router.put('/me/chat-folder-order', asyncHandler(async (req, res) => {
  const filterIds = Array.isArray(req.body.filterIds) ? req.body.filterIds : [];
  await query(
    `
      INSERT INTO user_chat_folder_settings (account_id, folders_json, filter_order_json, quiet_room_ids_json, pinned_room_ids_json, updated_at)
      VALUES ($1, '[]', $2, '[]', '[]', now())
      ON CONFLICT (account_id) DO UPDATE SET filter_order_json = EXCLUDED.filter_order_json, updated_at = now()
    `,
    [req.principal.userId, JSON.stringify(filterIds)]
  );
  res.json(filterIds);
}));

router.get('/me/quiet-chat-rooms', asyncHandler(async (req, res) => {
  const result = await query('SELECT quiet_room_ids_json FROM user_chat_folder_settings WHERE account_id = $1', [req.principal.userId]);
  res.json(JSON.parse(result.rows[0] && result.rows[0].quiet_room_ids_json || '[]'));
}));

router.put('/me/quiet-chat-rooms', asyncHandler(async (req, res) => {
  const roomIds = Array.isArray(req.body.roomIds) ? req.body.roomIds : [];
  await query(
    `
      INSERT INTO user_chat_folder_settings (account_id, folders_json, filter_order_json, quiet_room_ids_json, pinned_room_ids_json, updated_at)
      VALUES ($1, '[]', '[]', $2, '[]', now())
      ON CONFLICT (account_id) DO UPDATE SET quiet_room_ids_json = EXCLUDED.quiet_room_ids_json, updated_at = now()
    `,
    [req.principal.userId, JSON.stringify(roomIds)]
  );
  res.json(roomIds);
}));

router.get('/', asyncHandler(async (req, res) => {
  res.json(await profilesForPrincipal(req.principal));
}));

router.get('/company/employees/search', asyncHandler(async (req, res) => {
  const companyName = await effectiveCompany(req.principal, req);
  const name = `%${String(req.query.name || '').trim()}%`;
  const phone = `%${String(req.query.phoneNumber || '').trim()}%`;
  const email = `%${String(req.query.email || '').trim()}%`;
  const result = await query(
    `
      SELECT a.id, a.email, a.display_name, a.role,
             p.department, p.company_name, p.position, p.nickname, p.phone_number,
             p.contact_email, p.gender, p.birth_date, p.status, p.presence_updated_at,
             p.avatar_color, p.status_message, p.avatar_image_url,
             p.profile_background_color, p.profile_background_image_url
      FROM user_accounts a
      LEFT JOIN user_profiles p ON p.account_id = a.id
      WHERE COALESCE(p.company_name, 'ABBA-S') = $1
        AND ($2 = '%%' OR a.display_name ILIKE $2 OR p.nickname ILIKE $2)
        AND ($3 = '%%' OR p.phone_number ILIKE $3)
        AND ($4 = '%%' OR a.email ILIKE $4)
      ORDER BY a.display_name
      LIMIT 100
    `,
    [companyName, name, phone, email]
  );
  res.json(result.rows.map((row) => toProfileResponse(row)));
}));

router.post('/company/employees', asyncHandler(async (req, res) => {
  const account = await accountWithProfile(req.body.accountId || req.body.userId);
  if (!account) {
    throw notFound('Employee not found.');
  }
  res.json(toProfileResponse(account));
}));

router.post('/company/blocked-employees', asyncHandler(async (req, res) => {
  const account = await accountWithProfile(req.body.accountId || req.body.userId);
  if (!account) {
    throw notFound('Employee not found.');
  }
  res.json(toProfileResponse(account, true));
}));

router.delete('/company/blocked-employees', asyncHandler(async (req, res) => {
  const account = await accountWithProfile(req.body.accountId || req.body.userId);
  if (!account) {
    throw notFound('Employee not found.');
  }
  res.json(toProfileResponse(account, false));
}));

module.exports = router;
