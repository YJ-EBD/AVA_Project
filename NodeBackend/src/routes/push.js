const express = require('express');
const { query } = require('../db');
const { asyncHandler } = require('../errors');
const { authRequired } = require('../services/authService');

function mobilePushResponse(row) {
  let data = {};
  try {
    data = row.data_json ? JSON.parse(row.data_json) : {};
  } catch {
    data = {};
  }
  const type = String(row.type || '').trim().toLowerCase().replace(/[.-]/g, '_');
  return {
    id: row.id,
    type,
    title: row.title,
    body: row.body,
    roomId: row.room_id,
    roomTitle: row.room_title,
    senderName: row.sender_name,
    senderNickname: row.sender_nickname,
    avatarColor: row.avatar_color,
    sourceType: row.source_type,
    sourceId: row.source_id,
    createdAt: row.created_at,
    data
  };
}

const router = express.Router();
router.use(authRequired);

router.get('/events', asyncHandler(async (req, res) => {
  const limit = Math.max(1, Math.min(Number(req.query.limit) || 50, 200));
  const after = req.query.after ? new Date(req.query.after) : null;
  const result = await query(
    `
      SELECT e.*
      FROM mobile_push_events e
      WHERE e.account_id = $1
        AND ($2::timestamptz IS NULL OR e.created_at > $2::timestamptz)
        AND (
          replace(replace(lower(e.type), '.', '_'), '-', '_') <> 'chat_message'
          OR e.source_id IS NULL
          OR NOT EXISTS (
            SELECT 1
            FROM chat_message_read_receipts rr
            WHERE rr.account_id = e.account_id
              AND rr.message_id::text = e.source_id
          )
        )
      ORDER BY e.created_at DESC
      LIMIT $3
    `,
    [req.principal.userId, after, limit]
  );
  res.json(result.rows.reverse().map(mobilePushResponse));
}));

router.post('/devices/heartbeat', asyncHandler(async (req, res) => {
  res.json({ enabled: true, transport: 'ava-websocket' });
}));

module.exports = router;
