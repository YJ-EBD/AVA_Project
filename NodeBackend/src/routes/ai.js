const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const express = require('express');
const multer = require('multer');
const mime = require('mime-types');
const { randomUUID } = require('crypto');
const config = require('../config');
const { query } = require('../db');
const { asyncHandler, badRequest, notFound } = require('../errors');
const { authRequired } = require('../services/authService');
const { effectiveCompany } = require('../services/profileService');

function cleanRelativePath(value) {
  const raw = String(value || '').replace(/\0/g, '').replace(/\\/g, '/').trim();
  const withoutDrive = raw.replace(/^[a-zA-Z]:/, '').replace(/^\/+/, '');
  const normalized = path.posix.normalize(withoutDrive);
  return normalized === '.' ? '' : normalized.replace(/^(\.\.\/)+/, '');
}

function userWorkspaceRoot(principal) {
  return path.join(config.backendDir, 'AiWorkspace', principal.userId);
}

function resolveWorkspacePath(principal, requestedPath = '') {
  const root = path.resolve(userWorkspaceRoot(principal));
  const relativePath = cleanRelativePath(requestedPath);
  const fullPath = path.resolve(root, relativePath);
  if (fullPath !== root && !fullPath.startsWith(`${root}${path.sep}`)) {
    throw badRequest('Workspace path is outside the allowed directory.');
  }
  return { root, relativePath, fullPath };
}

async function ensureWorkspace(principal) {
  const root = userWorkspaceRoot(principal);
  await fsp.mkdir(root, { recursive: true });
  return root;
}

async function fileItem(principal, fullPath, includeContent = false) {
  const root = path.resolve(userWorkspaceRoot(principal));
  const stat = await fsp.stat(fullPath);
  const relativePath = path.relative(root, fullPath).replace(/\\/g, '/');
  const directory = stat.isDirectory();
  let content = '';
  if (includeContent && !directory) {
    const buffer = await fsp.readFile(fullPath);
    content = buffer.length > 512 * 1024 ? buffer.subarray(0, 512 * 1024).toString('utf8') : buffer.toString('utf8');
  }
  return {
    type: directory ? 'directory' : 'file',
    title: path.basename(fullPath),
    subtitle: directory ? 'Folder' : `${stat.size} bytes`,
    path: relativePath,
    url: '',
    imageUrl: '',
    content,
    size: directory ? null : stat.size,
    updatedAt: stat.mtime.toISOString(),
    roomCode: ''
  };
}

async function listRecursive(principal, root, queryText, limit = 200) {
  const items = [];
  async function visit(directory) {
    if (items.length >= limit) {
      return;
    }
    const entries = await fsp.readdir(directory, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name.startsWith('.')) {
        continue;
      }
      const fullPath = path.join(directory, entry.name);
      const item = await fileItem(principal, fullPath);
      if (!queryText || item.title.toLowerCase().includes(queryText.toLowerCase()) || item.path.toLowerCase().includes(queryText.toLowerCase())) {
        items.push(item);
      }
      if (entry.isDirectory()) {
        await visit(fullPath);
      }
      if (items.length >= limit) {
        break;
      }
    }
  }
  await visit(root);
  return items;
}

function messageResponse(row) {
  return {
    id: row.id,
    role: String(row.role || '').toLowerCase(),
    content: row.content,
    createdAt: row.created_at,
    references: []
  };
}

function emptyCalendarWorkspace(mode = '') {
  return {
    handled: false,
    mutation: false,
    requiresClarification: false,
    mode,
    status: '',
    selectedEventId: '',
    summary: null,
    events: [],
    conflicts: [],
    availability: [],
    metadata: {}
  };
}

function calendarCard(row) {
  return {
    id: row.id,
    title: row.title || '',
    description: row.description || '',
    startAt: row.start_at || null,
    endAt: row.end_at || null,
    allDay: Boolean(row.all_day),
    location: row.location || '',
    status: row.status || 'SCHEDULED',
    statusLabel: row.status || 'SCHEDULED',
    categoryName: row.category_name || '',
    teamId: row.team_id || '',
    teamLabel: row.team_id || '',
    importance: row.importance || 'NORMAL',
    importanceLabel: row.importance || 'NORMAL',
    color: row.color || row.category_color || '',
    hasAzoom: Number(row.azoom_count || 0) > 0,
    hasChat: Number(row.chat_count || 0) > 0,
    hasFiles: Number(row.file_count || 0) > 0,
    hasNotion: Number(row.notion_count || 0) > 0,
    memo: row.memo || ''
  };
}

async function calendarWorkspace(principal, mode) {
  const now = new Date();
  const start = new Date(now);
  const end = new Date(now);
  if (mode === 'week') {
    const day = start.getDay() || 7;
    start.setDate(start.getDate() - day + 1);
    start.setHours(0, 0, 0, 0);
    end.setTime(start.getTime());
    end.setDate(end.getDate() + 7);
  } else {
    start.setHours(0, 0, 0, 0);
    end.setTime(start.getTime());
    end.setDate(end.getDate() + 1);
  }
  const result = await query(
    `
      SELECT e.*, c.name AS category_name, c.color AS category_color,
             (SELECT COUNT(*) FROM calendar_event_azoom_links a WHERE a.event_id = e.id) AS azoom_count,
             (SELECT COUNT(*) FROM calendar_event_chat_links ch WHERE ch.event_id = e.id) AS chat_count,
             (SELECT COUNT(*) FROM calendar_event_files f WHERE f.event_id = e.id) AS file_count,
             (SELECT COUNT(*) FROM calendar_event_notion_links n WHERE n.event_id = e.id) AS notion_count
      FROM calendar_events e
      LEFT JOIN calendar_categories c ON c.id = e.category_id
      WHERE e.deleted_at IS NULL
        AND e.end_at >= $1::timestamptz
        AND e.start_at < $2::timestamptz
        AND (e.owner_user_id = $3 OR e.visibility <> 'PRIVATE')
      ORDER BY e.start_at ASC
      LIMIT 100
    `,
    [start.toISOString(), end.toISOString(), principal.userId]
  );
  const countsByStatus = {};
  for (const row of result.rows) {
    countsByStatus[row.status || 'SCHEDULED'] = (countsByStatus[row.status || 'SCHEDULED'] || 0) + 1;
  }
  return {
    handled: true,
    mutation: false,
    requiresClarification: false,
    mode,
    status: result.rows.length ? 'READY' : 'EMPTY',
    selectedEventId: result.rows[0] ? result.rows[0].id : '',
    summary: {
      title: mode === 'week' ? 'This week' : 'Today',
      rangeStart: start.toISOString(),
      rangeEnd: end.toISOString(),
      totalCount: result.rows.length,
      countsByStatus
    },
    events: result.rows.map(calendarCard),
    conflicts: [],
    availability: [],
    metadata: {}
  };
}

function createAiRouter(chatService = null) {
  const router = express.Router();
  const uploadRoot = path.join(config.backendDir, 'AiWorkspaceUploads');
  fs.mkdirSync(uploadRoot, { recursive: true });
  const upload = multer({ dest: uploadRoot });

  router.use(authRequired);

  router.get('/messages', asyncHandler(async (req, res) => {
    const result = await query(
      `
        SELECT *
        FROM ava_ai_messages
        WHERE account_id = $1
        ORDER BY created_at ASC
        LIMIT 200
      `,
      [req.principal.userId]
    );
    res.json(result.rows.map(messageResponse));
  }));

  router.post('/messages', asyncHandler(async (req, res) => {
    const content = String(req.body.content || '').trim();
    if (!content) {
      throw badRequest('Message content is required.');
    }
    const companyName = await effectiveCompany(req.principal, req);
    const conversation = randomUUID();
    const userId = randomUUID();
    const assistantId = randomUUID();
    const answer = 'NodeBackend AI gateway is online. Local LLM orchestration can be connected through LLM_Server while this API keeps the AVA client contract stable.';
    const inserted = await query(
      `
        WITH user_message AS (
          INSERT INTO ava_ai_messages (id, conversation_id, account_id, company_name, role, content, model, created_at)
          VALUES ($1,$2,$3,$4,'USER',$5,NULL,now())
          RETURNING *
        ),
        assistant_message AS (
          INSERT INTO ava_ai_messages (id, conversation_id, account_id, company_name, role, content, model, created_at)
          VALUES ($6,$2,$3,$4,'ASSISTANT',$7,'node-gateway',now())
          RETURNING *
        )
        SELECT 'user' AS kind, * FROM user_message
        UNION ALL
        SELECT 'assistant' AS kind, * FROM assistant_message
      `,
      [userId, conversation, req.principal.userId, companyName, content, assistantId, answer]
    );
    const userMessage = inserted.rows.find((row) => row.kind === 'user');
    const assistantMessage = inserted.rows.find((row) => row.kind === 'assistant');
    const mode = /week|주|이번 주/i.test(content) ? 'week' : 'today';
    const scheduleSignal = /일정|calendar|schedule|회의|미팅/i.test(content);
    res.json({
      userMessage: messageResponse(userMessage),
      assistantMessage: messageResponse(assistantMessage),
      workspaceItems: [],
      workspaceStatus: '',
      agentTask: null,
      calendarWorkspace: scheduleSignal ? await calendarWorkspace(req.principal, mode) : emptyCalendarWorkspace('')
    });
  }));

  router.post('/messages/reset', asyncHandler(async (req, res) => {
    await query('DELETE FROM ava_ai_messages WHERE account_id = $1', [req.principal.userId]);
    res.status(204).end();
  }));

  router.get('/workspace/files', asyncHandler(async (req, res) => {
    await ensureWorkspace(req.principal);
    const { fullPath } = resolveWorkspacePath(req.principal, req.query.path || '');
    if (!fs.existsSync(fullPath)) {
      await fsp.mkdir(fullPath, { recursive: true });
    }
    const stat = await fsp.stat(fullPath);
    if (!stat.isDirectory()) {
      res.json([await fileItem(req.principal, fullPath)]);
      return;
    }
    if (req.query.query) {
      res.json(await listRecursive(req.principal, fullPath, String(req.query.query)));
      return;
    }
    const entries = await fsp.readdir(fullPath, { withFileTypes: true });
    const items = [];
    for (const entry of entries.filter((item) => !item.name.startsWith('.'))) {
      items.push(await fileItem(req.principal, path.join(fullPath, entry.name)));
    }
    items.sort((left, right) => {
      if (left.type !== right.type) {
        return left.type === 'directory' ? -1 : 1;
      }
      return left.title.localeCompare(right.title);
    });
    res.json(items);
  }));

  router.get('/workspace/files/content', asyncHandler(async (req, res) => {
    const { fullPath } = resolveWorkspacePath(req.principal, req.query.path);
    if (!fs.existsSync(fullPath)) {
      throw notFound('Workspace file not found.');
    }
    res.json(await fileItem(req.principal, fullPath, true));
  }));

  router.get('/workspace/files/preview', asyncHandler(async (req, res) => {
    const { fullPath } = resolveWorkspacePath(req.principal, req.query.path);
    if (!fs.existsSync(fullPath)) {
      throw notFound('Workspace file not found.');
    }
    const stat = await fsp.stat(fullPath);
    if (stat.isDirectory()) {
      throw badRequest('Cannot preview a directory.');
    }
    res.type(mime.lookup(fullPath) || 'application/octet-stream');
    res.setHeader('Content-Length', stat.size);
    res.setHeader('Content-Disposition', `inline; filename="${path.basename(fullPath).replace(/"/g, '')}"`);
    fs.createReadStream(fullPath).pipe(res);
  }));

  router.post('/workspace/files', asyncHandler(async (req, res) => {
    await ensureWorkspace(req.principal);
    const { fullPath } = resolveWorkspacePath(req.principal, req.body.path);
    if (!req.body.path) {
      throw badRequest('Workspace path is required.');
    }
    await fsp.mkdir(path.dirname(fullPath), { recursive: true });
    if (req.body.directory) {
      await fsp.mkdir(fullPath, { recursive: true });
    } else {
      await fsp.writeFile(fullPath, String(req.body.content || ''), 'utf8');
    }
    res.json(await fileItem(req.principal, fullPath, !req.body.directory));
  }));

  router.put('/workspace/files', asyncHandler(async (req, res) => {
    const { fullPath } = resolveWorkspacePath(req.principal, req.body.path);
    if (!fs.existsSync(fullPath)) {
      throw notFound('Workspace file not found.');
    }
    let targetPath = fullPath;
    if (req.body.newPath) {
      const resolved = resolveWorkspacePath(req.principal, req.body.newPath);
      await fsp.mkdir(path.dirname(resolved.fullPath), { recursive: true });
      await fsp.rename(fullPath, resolved.fullPath);
      targetPath = resolved.fullPath;
    }
    const stat = await fsp.stat(targetPath);
    if (req.body.content != null && !stat.isDirectory()) {
      await fsp.writeFile(targetPath, String(req.body.content), 'utf8');
    }
    res.json(await fileItem(req.principal, targetPath, !stat.isDirectory()));
  }));

  router.delete('/workspace/files', asyncHandler(async (req, res) => {
    const { fullPath } = resolveWorkspacePath(req.principal, req.query.path);
    if (!fs.existsSync(fullPath)) {
      throw notFound('Workspace file not found.');
    }
    const item = await fileItem(req.principal, fullPath);
    await fsp.rm(fullPath, { recursive: true, force: true });
    res.json(item);
  }));

  router.post('/workspace/uploads', upload.array('files'), asyncHandler(async (req, res) => {
    const root = await ensureWorkspace(req.principal);
    const items = [];
    for (const file of req.files || []) {
      const targetName = path.basename(file.originalname || file.filename).replace(/[<>:"|?*]/g, '_');
      const target = path.join(root, targetName);
      await fsp.rename(file.path, target);
      items.push(await fileItem(req.principal, target));
    }
    res.json(items);
  }));

  router.post('/workspace/send-to-chat', asyncHandler(async (req, res) => {
    const paths = Array.isArray(req.body.paths) ? req.body.paths : [];
    const items = [];
    for (const itemPath of paths) {
      const { fullPath } = resolveWorkspacePath(req.principal, itemPath);
      if (fs.existsSync(fullPath)) {
        items.push(await fileItem(req.principal, fullPath));
      }
    }
    if (chatService && req.body.roomCode && items.length > 0) {
      const message = req.body.message || `Workspace files: ${items.map((item) => item.title).join(', ')}`;
      await chatService.sendMessage(req.body.roomCode, { content: message, mentions: [] }, req.principal);
    }
    res.json({ status: 'sent', items });
  }));

  router.get('/calendar/workspace', asyncHandler(async (req, res) => {
    res.json(await calendarWorkspace(req.principal, String(req.query.mode || 'today')));
  }));

  router.get('/notion/search', (req, res) => {
    res.json([]);
  });

  router.get('/notion/pages/:id', (req, res) => {
    res.json({
      id: req.params.id,
      object: req.query.object || 'page',
      title: '',
      subtitle: '',
      url: '',
      icon: '',
      coverUrl: '',
      content: '',
      properties: [],
      blocks: [],
      children: [],
      updatedAt: new Date().toISOString()
    });
  });

  router.post('/notion/command', (req, res) => {
    res.json({
      answer: 'Notion integration is not configured on this NodeBackend instance.',
      status: 'NOT_CONFIGURED',
      results: [],
      requiresApproval: false,
      approvalTitle: '',
      approvalDescription: '',
      executionMode: 'node'
    });
  });

  router.post('/notion/uploads', upload.array('files'), (req, res) => {
    res.json({
      answer: 'Files were received by NodeBackend, but Notion upload is not configured.',
      status: 'NOT_CONFIGURED',
      results: [],
      requiresApproval: false,
      approvalTitle: '',
      approvalDescription: '',
      executionMode: 'node'
    });
  });

  return router;
}

module.exports = {
  createAiRouter,
  emptyCalendarWorkspace
};
