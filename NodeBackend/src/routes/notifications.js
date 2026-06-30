const express = require('express');
const { query } = require('../db');
const { asyncHandler, notFound } = require('../errors');
const { authRequired } = require('../services/authService');

const router = express.Router();
router.use(authRequired);

function toNotification(row) {
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    body: row.body,
    sourceType: row.source_type,
    sourceId: row.source_id,
    createdAt: row.created_at,
    readAt: row.read_at,
    read: Boolean(row.read_at)
  };
}

router.get('/', asyncHandler(async (req, res) => {
  const result = await query(
    `
      SELECT *
      FROM notifications
      WHERE account_id = $1
      ORDER BY created_at DESC
      LIMIT 100
    `,
    [req.principal.userId]
  );
  const unread = result.rows.filter((row) => !row.read_at).length;
  res.json({
    unreadCount: unread,
    items: result.rows.map(toNotification)
  });
}));

router.post('/:id/read', asyncHandler(async (req, res) => {
  const result = await query(
    `
      UPDATE notifications
      SET read_at = COALESCE(read_at, now())
      WHERE id = $1 AND account_id = $2
      RETURNING *
    `,
    [req.params.id, req.principal.userId]
  );
  if (!result.rows[0]) {
    throw notFound('Notification not found.');
  }
  res.json(toNotification(result.rows[0]));
}));

router.post('/read-all', asyncHandler(async (req, res) => {
  await query(
    'UPDATE notifications SET read_at = COALESCE(read_at, now()) WHERE account_id = $1',
    [req.principal.userId]
  );
  const result = await query(
    'SELECT * FROM notifications WHERE account_id = $1 ORDER BY created_at DESC LIMIT 100',
    [req.principal.userId]
  );
  res.json({
    unreadCount: 0,
    items: result.rows.map(toNotification)
  });
}));

module.exports = router;
