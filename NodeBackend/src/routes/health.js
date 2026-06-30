const express = require('express');
const { asyncHandler } = require('../errors');
const { query } = require('../db');

const router = express.Router();

router.get('/health', (req, res) => {
  res.json({
    service: 'ava-backend',
    runtime: 'node',
    status: 'UP'
  });
});

router.get('/readiness', asyncHandler(async (req, res) => {
  await query('SELECT 1');
  res.json({
    service: 'ava-backend',
    runtime: 'node',
    status: 'READY',
    productionLike: false,
    problems: []
  });
}));

module.exports = router;
