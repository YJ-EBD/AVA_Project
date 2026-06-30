const express = require('express');
const { randomUUID } = require('crypto');
const { query, tx } = require('../db');
const { asyncHandler, notFound } = require('../errors');
const { authRequired } = require('../services/authService');

const router = express.Router();
router.use(authRequired);

function emptyToNull(value) {
  return value == null || String(value).trim() === '' ? null : value;
}

function categoryResponse(row) {
  return {
    id: row.id,
    name: row.name,
    color: row.color,
    icon: row.icon || null,
    scope: row.scope || 'USER',
    defaultCategory: Boolean(row.is_default),
    sortOrder: Number(row.sort_order || 0)
  };
}

async function loadEvent(eventId) {
  const event = await query(
    `
      SELECT e.*, c.name AS category_name, c.color AS category_color, c.icon AS category_icon,
             c.scope AS category_scope, c.is_default AS category_default, c.sort_order AS category_sort_order
      FROM calendar_events e
      LEFT JOIN calendar_categories c ON c.id = e.category_id
      WHERE e.id = $1 AND e.deleted_at IS NULL
    `,
    [eventId]
  );
  if (!event.rows[0]) {
    return null;
  }
  const [attendees, reminders, recurrence, files, notionLinks, chatLinks, azoomLinks] = await Promise.all([
    query('SELECT * FROM calendar_event_attendees WHERE event_id = $1 ORDER BY created_at ASC', [eventId]),
    query('SELECT * FROM calendar_event_reminders WHERE event_id = $1 ORDER BY remind_before_minutes ASC', [eventId]),
    query('SELECT * FROM calendar_event_recurrences WHERE event_id = $1', [eventId]),
    query('SELECT * FROM calendar_event_files WHERE event_id = $1 ORDER BY linked_at ASC', [eventId]),
    query('SELECT * FROM calendar_event_notion_links WHERE event_id = $1 ORDER BY linked_at ASC', [eventId]),
    query('SELECT * FROM calendar_event_chat_links WHERE event_id = $1 ORDER BY linked_at ASC', [eventId]),
    query('SELECT * FROM calendar_event_azoom_links WHERE event_id = $1 ORDER BY linked_at ASC', [eventId])
  ]);
  return eventResponse(
    event.rows[0],
    attendees.rows,
    reminders.rows,
    recurrence.rows[0],
    files.rows,
    notionLinks.rows,
    chatLinks.rows,
    azoomLinks.rows
  );
}

function eventResponse(row, attendees = [], reminders = [], recurrence = null, files = [], notionLinks = [], chatLinks = [], azoomLinks = []) {
  return {
    id: row.id,
    title: row.title,
    description: row.description || null,
    startAt: row.start_at,
    endAt: row.end_at,
    occurrenceStartAt: null,
    occurrenceEndAt: null,
    allDay: Boolean(row.all_day),
    location: row.location || null,
    categoryId: row.category_id || null,
    category: row.category_id ? categoryResponse({
      id: row.category_id,
      name: row.category_name || '',
      color: row.category_color || '#8A8F98',
      icon: row.category_icon || null,
      scope: row.category_scope || 'USER',
      is_default: row.category_default || false,
      sort_order: row.category_sort_order || 0
    }) : null,
    color: row.color || null,
    status: row.status || 'SCHEDULED',
    meetingStatus: row.meeting_status || 'RESERVED',
    visibility: row.visibility || 'ATTENDEES',
    detailVisibility: row.detail_visibility || 'FULL',
    ownerUserId: row.owner_user_id,
    createdBy: row.created_by,
    updatedBy: row.updated_by || null,
    memo: row.memo || null,
    projectName: row.project_name || null,
    teamId: row.team_id || null,
    importance: row.importance || 'NORMAL',
    attendees: attendees.map((item) => ({
      id: item.id,
      userId: item.user_id || null,
      displayName: item.display_name,
      department: item.department || null,
      position: item.position || null,
      email: item.email || null,
      responseStatus: item.response_status || 'PENDING',
      responseMessage: item.response_message || null,
      respondedAt: item.responded_at || null
    })),
    reminders: reminders.map((item) => ({
      id: item.id,
      remindBeforeMinutes: Number(item.remind_before_minutes || 10),
      reminderType: item.reminder_type || 'IN_APP',
      targetType: item.target_type || 'OWNER',
      targetId: item.target_id || null,
      sent: Boolean(item.is_sent)
    })),
    recurrence: recurrence ? {
      id: recurrence.id,
      recurrenceType: recurrence.recurrence_type || 'NONE',
      intervalValue: Number(recurrence.interval_value || 1),
      daysOfWeek: recurrence.days_of_week || null,
      dayOfMonth: recurrence.day_of_month || null,
      endType: recurrence.end_type || 'NEVER',
      untilDate: recurrence.until_date || null,
      occurrenceCount: recurrence.occurrence_count || null,
      rrule: recurrence.rrule || null,
      timezone: recurrence.timezone || 'Asia/Seoul'
    } : null,
    files: files.map((item) => ({
      id: item.id,
      fileId: item.file_id || null,
      fileName: item.file_name,
      filePath: item.file_path || null,
      fileType: item.file_type || null,
      fileSize: item.file_size == null ? null : Number(item.file_size),
      sourceType: item.source_type || 'NAS'
    })),
    notionLinks: notionLinks.map((item) => ({
      id: item.id,
      notionPageId: item.notion_page_id || null,
      notionDatabaseId: item.notion_database_id || null,
      notionTitle: item.notion_title,
      notionUrl: item.notion_url || null
    })),
    chatLinks: chatLinks.map((item) => ({
      id: item.id,
      chatRoomId: item.chat_room_id,
      chatRoomName: item.chat_room_name || null,
      sourceMessageId: item.source_message_id || null,
      sourceMessagePreview: item.source_message_preview || null
    })),
    azoomLinks: azoomLinks.map((item) => ({
      id: item.id,
      azoomMeetingId: item.azoom_meeting_id || null,
      azoomRoomId: item.azoom_room_id || null,
      azoomJoinUrl: item.azoom_join_url || null,
      azoomRecordingId: item.azoom_recording_id || null,
      azoomTranscriptId: item.azoom_transcript_id || null,
      azoomMinutesId: item.azoom_minutes_id || null
    })),
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

async function replaceChildren(client, eventId, body) {
  await client.query('DELETE FROM calendar_event_attendees WHERE event_id = $1', [eventId]);
  for (const item of body.attendees || []) {
    await client.query(
      `
        INSERT INTO calendar_event_attendees (
          id, event_id, user_id, display_name, department, position, email,
          response_status, response_message, responded_at, created_at
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,now())
      `,
      [
        randomUUID(),
        eventId,
        emptyToNull(item.userId),
        item.displayName || '',
        emptyToNull(item.department),
        emptyToNull(item.position),
        emptyToNull(item.email),
        item.responseStatus || 'PENDING',
        emptyToNull(item.responseMessage),
        emptyToNull(item.respondedAt)
      ]
    );
  }
  await client.query('DELETE FROM calendar_event_reminders WHERE event_id = $1', [eventId]);
  for (const item of body.reminders || []) {
    await client.query(
      `
        INSERT INTO calendar_event_reminders (
          id, event_id, remind_before_minutes, reminder_type, target_type, target_id, is_sent, created_at
        )
        VALUES ($1,$2,$3,$4,$5,$6,false,now())
      `,
      [randomUUID(), eventId, item.remindBeforeMinutes || 10, item.reminderType || 'IN_APP', item.targetType || 'OWNER', emptyToNull(item.targetId)]
    );
  }
  await client.query('DELETE FROM calendar_event_recurrences WHERE event_id = $1', [eventId]);
  if (body.recurrence) {
    await client.query(
      `
        INSERT INTO calendar_event_recurrences (
          id, event_id, recurrence_type, interval_value, days_of_week, day_of_month,
          end_type, until_date, occurrence_count, rrule, timezone, created_at
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,now())
      `,
      [
        randomUUID(),
        eventId,
        body.recurrence.recurrenceType || 'NONE',
        body.recurrence.intervalValue || 1,
        emptyToNull(body.recurrence.daysOfWeek),
        body.recurrence.dayOfMonth || null,
        body.recurrence.endType || 'NEVER',
        body.recurrence.untilDate || null,
        body.recurrence.occurrenceCount || null,
        emptyToNull(body.recurrence.rrule),
        body.recurrence.timezone || 'Asia/Seoul'
      ]
    );
  }
}

router.get('/events', asyncHandler(async (req, res) => {
  const result = await query(
    `
      SELECT e.*, c.name AS category_name, c.color AS category_color, c.icon AS category_icon,
             c.scope AS category_scope, c.is_default AS category_default, c.sort_order AS category_sort_order
      FROM calendar_events e
      LEFT JOIN calendar_categories c ON c.id = e.category_id
      WHERE e.deleted_at IS NULL
        AND ($1::timestamptz IS NULL OR e.end_at >= $1::timestamptz)
        AND ($2::timestamptz IS NULL OR e.start_at <= $2::timestamptz)
        AND ($3::uuid IS NULL OR e.category_id = $3::uuid)
        AND ($4::varchar IS NULL OR e.team_id = $4::varchar)
        AND ($5::varchar IS NULL OR e.status = $5::varchar)
        AND ($6::varchar IS NULL OR lower(e.title) LIKE lower('%' || $6::varchar || '%'))
      ORDER BY e.start_at ASC
      LIMIT $7
    `,
    [
      req.query.startAt || null,
      req.query.endAt || null,
      req.query.categoryId || null,
      req.query.teamId || null,
      req.query.status || null,
      req.query.query || null,
      Math.max(1, Math.min(Number(req.query.size) || 300, 1000))
    ]
  );
  const responses = [];
  for (const row of result.rows) {
    responses.push(await loadEvent(row.id));
  }
  res.json(responses.filter(Boolean));
}));

router.get('/events/:id', asyncHandler(async (req, res) => {
  const event = await loadEvent(req.params.id);
  if (!event) {
    throw notFound('Calendar event not found.');
  }
  res.json(event);
}));

router.post('/events', asyncHandler(async (req, res) => {
  const eventId = randomUUID();
  await tx(async (client) => {
    await client.query(
      `
        INSERT INTO calendar_events (
          id, title, description, start_at, end_at, all_day, location, category_id,
          color, status, meeting_status, visibility, detail_visibility, owner_user_id,
          created_by, updated_by, memo, project_name, team_id, importance, created_at, updated_at
        )
        VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$14,$14,$15,$16,$17,$18,now(),now())
      `,
      [
        eventId,
        req.body.title || 'Untitled',
        emptyToNull(req.body.description),
        req.body.startAt || new Date().toISOString(),
        req.body.endAt || req.body.startAt || new Date().toISOString(),
        Boolean(req.body.allDay),
        emptyToNull(req.body.location),
        emptyToNull(req.body.categoryId),
        emptyToNull(req.body.color),
        req.body.status || 'SCHEDULED',
        req.body.meetingStatus || 'RESERVED',
        req.body.visibility || 'ATTENDEES',
        req.body.detailVisibility || 'FULL',
        req.principal.userId,
        emptyToNull(req.body.memo),
        emptyToNull(req.body.projectName),
        emptyToNull(req.body.teamId),
        req.body.importance || 'NORMAL'
      ]
    );
    await replaceChildren(client, eventId, req.body);
  });
  res.json(await loadEvent(eventId));
}));

router.patch('/events/:id', asyncHandler(async (req, res) => {
  await tx(async (client) => {
    await client.query(
      `
        UPDATE calendar_events
        SET title = COALESCE($2, title),
            description = $3,
            start_at = COALESCE($4, start_at),
            end_at = COALESCE($5, end_at),
            all_day = COALESCE($6, all_day),
            location = $7,
            category_id = $8,
            color = $9,
            status = COALESCE($10, status),
            meeting_status = COALESCE($11, meeting_status),
            visibility = COALESCE($12, visibility),
            detail_visibility = COALESCE($13, detail_visibility),
            updated_by = $14,
            memo = $15,
            project_name = $16,
            team_id = $17,
            importance = COALESCE($18, importance),
            updated_at = now()
        WHERE id = $1 AND deleted_at IS NULL
      `,
      [
        req.params.id,
        req.body.title || null,
        emptyToNull(req.body.description),
        req.body.startAt || null,
        req.body.endAt || null,
        typeof req.body.allDay === 'boolean' ? req.body.allDay : null,
        emptyToNull(req.body.location),
        emptyToNull(req.body.categoryId),
        emptyToNull(req.body.color),
        req.body.status || null,
        req.body.meetingStatus || null,
        req.body.visibility || null,
        req.body.detailVisibility || null,
        req.principal.userId,
        emptyToNull(req.body.memo),
        emptyToNull(req.body.projectName),
        emptyToNull(req.body.teamId),
        req.body.importance || null
      ]
    );
    await replaceChildren(client, req.params.id, req.body);
  });
  const event = await loadEvent(req.params.id);
  if (!event) {
    throw notFound('Calendar event not found.');
  }
  res.json(event);
}));

router.delete('/events/:id', asyncHandler(async (req, res) => {
  await query('UPDATE calendar_events SET deleted_at = now(), updated_at = now() WHERE id = $1', [req.params.id]);
  res.status(204).end();
}));

router.get('/categories', asyncHandler(async (req, res) => {
  const result = await query(
    `
      SELECT *
      FROM calendar_categories
      WHERE owner_user_id IS NULL OR owner_user_id = $1
      ORDER BY is_default DESC, sort_order ASC, name ASC
    `,
    [req.principal.userId]
  );
  res.json(result.rows.map(categoryResponse));
}));

router.post('/categories', asyncHandler(async (req, res) => {
  const result = await query(
    `
      INSERT INTO calendar_categories (id, name, color, icon, scope, owner_user_id, is_default, sort_order, created_at, updated_at)
      VALUES ($1,$2,$3,$4,$5,$6,false,0,now(),now())
      RETURNING *
    `,
    [randomUUID(), req.body.name || 'Category', req.body.color || '#8A8F98', req.body.icon || null, req.body.scope || 'USER', req.principal.userId]
  );
  res.json(categoryResponse(result.rows[0]));
}));

router.patch('/categories/:id', asyncHandler(async (req, res) => {
  const result = await query(
    `
      UPDATE calendar_categories
      SET name = COALESCE($2, name),
          color = COALESCE($3, color),
          icon = $4,
          scope = COALESCE($5, scope),
          updated_at = now()
      WHERE id = $1 AND (owner_user_id = $6 OR owner_user_id IS NULL)
      RETURNING *
    `,
    [
      req.params.id,
      req.body.name || null,
      req.body.color || null,
      emptyToNull(req.body.icon),
      req.body.scope || null,
      req.principal.userId
    ]
  );
  if (!result.rows[0]) {
    throw notFound('Calendar category not found.');
  }
  res.json(categoryResponse(result.rows[0]));
}));

router.delete('/categories/:id', asyncHandler(async (req, res) => {
  await query('DELETE FROM calendar_categories WHERE id = $1 AND (owner_user_id = $2 OR owner_user_id IS NULL)', [req.params.id, req.principal.userId]);
  res.status(204).end();
}));

router.post('/events/:id/attendees', asyncHandler(async (req, res) => {
  const result = await query(
    `
      INSERT INTO calendar_event_attendees (
        id, event_id, user_id, display_name, department, position, email,
        response_status, response_message, responded_at, created_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,now())
      RETURNING *
    `,
    [
      randomUUID(),
      req.params.id,
      emptyToNull(req.body.userId),
      req.body.displayName || '',
      emptyToNull(req.body.department),
      emptyToNull(req.body.position),
      emptyToNull(req.body.email),
      req.body.responseStatus || 'PENDING',
      emptyToNull(req.body.responseMessage),
      emptyToNull(req.body.respondedAt)
    ]
  );
  const item = result.rows[0];
  res.json({
    id: item.id,
    userId: item.user_id || null,
    displayName: item.display_name,
    department: item.department || null,
    position: item.position || null,
    email: item.email || null,
    responseStatus: item.response_status,
    responseMessage: item.response_message || null,
    respondedAt: item.responded_at || null
  });
}));

router.patch('/events/:id/attendees/:attendeeId', asyncHandler(async (req, res) => {
  const result = await query(
    `
      UPDATE calendar_event_attendees
      SET display_name = COALESCE($3, display_name),
          department = $4,
          position = $5,
          email = $6,
          response_status = COALESCE($7, response_status),
          response_message = $8,
          responded_at = COALESCE($9, responded_at)
      WHERE event_id = $1 AND id = $2
      RETURNING *
    `,
    [
      req.params.id,
      req.params.attendeeId,
      req.body.displayName || null,
      emptyToNull(req.body.department),
      emptyToNull(req.body.position),
      emptyToNull(req.body.email),
      req.body.responseStatus || null,
      emptyToNull(req.body.responseMessage),
      emptyToNull(req.body.respondedAt)
    ]
  );
  if (!result.rows[0]) {
    throw notFound('Calendar attendee not found.');
  }
  const item = result.rows[0];
  res.json({
    id: item.id,
    userId: item.user_id || null,
    displayName: item.display_name,
    department: item.department || null,
    position: item.position || null,
    email: item.email || null,
    responseStatus: item.response_status,
    responseMessage: item.response_message || null,
    respondedAt: item.responded_at || null
  });
}));

router.delete('/events/:id/attendees/:attendeeId', asyncHandler(async (req, res) => {
  await query('DELETE FROM calendar_event_attendees WHERE event_id = $1 AND id = $2', [req.params.id, req.params.attendeeId]);
  res.status(204).end();
}));

router.post('/events/:id/reminders', asyncHandler(async (req, res) => {
  const result = await query(
    `
      INSERT INTO calendar_event_reminders (
        id, event_id, remind_before_minutes, reminder_type, target_type, target_id, is_sent, created_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,false,now())
      RETURNING *
    `,
    [
      randomUUID(),
      req.params.id,
      req.body.remindBeforeMinutes || 10,
      req.body.reminderType || 'IN_APP',
      req.body.targetType || 'OWNER',
      emptyToNull(req.body.targetId)
    ]
  );
  const item = result.rows[0];
  res.json({
    id: item.id,
    remindBeforeMinutes: Number(item.remind_before_minutes),
    reminderType: item.reminder_type,
    targetType: item.target_type,
    targetId: item.target_id || null,
    sent: Boolean(item.is_sent)
  });
}));

router.delete('/events/:id/reminders/:reminderId', asyncHandler(async (req, res) => {
  await query('DELETE FROM calendar_event_reminders WHERE event_id = $1 AND id = $2', [req.params.id, req.params.reminderId]);
  res.status(204).end();
}));

router.post('/events/:id/files', asyncHandler(async (req, res) => {
  const result = await query(
    `
      INSERT INTO calendar_event_files (
        id, event_id, file_id, file_name, file_path, file_type, file_size, source_type, linked_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,now())
      RETURNING *
    `,
    [
      randomUUID(),
      req.params.id,
      emptyToNull(req.body.fileId),
      req.body.fileName || 'file',
      emptyToNull(req.body.filePath),
      emptyToNull(req.body.fileType),
      req.body.fileSize || null,
      req.body.sourceType || 'NAS'
    ]
  );
  const item = result.rows[0];
  res.json({
    id: item.id,
    fileId: item.file_id || null,
    fileName: item.file_name,
    filePath: item.file_path || null,
    fileType: item.file_type || null,
    fileSize: item.file_size == null ? null : Number(item.file_size),
    sourceType: item.source_type
  });
}));

router.delete('/events/:id/files/:fileLinkId', asyncHandler(async (req, res) => {
  await query('DELETE FROM calendar_event_files WHERE event_id = $1 AND id = $2', [req.params.id, req.params.fileLinkId]);
  res.status(204).end();
}));

router.post('/events/:id/notion-links', asyncHandler(async (req, res) => {
  const result = await query(
    `
      INSERT INTO calendar_event_notion_links (
        id, event_id, notion_page_id, notion_database_id, notion_title, notion_url, linked_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,now())
      RETURNING *
    `,
    [
      randomUUID(),
      req.params.id,
      emptyToNull(req.body.notionPageId),
      emptyToNull(req.body.notionDatabaseId),
      req.body.notionTitle || 'Notion',
      emptyToNull(req.body.notionUrl)
    ]
  );
  const item = result.rows[0];
  res.json({
    id: item.id,
    notionPageId: item.notion_page_id || null,
    notionDatabaseId: item.notion_database_id || null,
    notionTitle: item.notion_title,
    notionUrl: item.notion_url || null
  });
}));

router.delete('/events/:id/notion-links/:linkId', asyncHandler(async (req, res) => {
  await query('DELETE FROM calendar_event_notion_links WHERE event_id = $1 AND id = $2', [req.params.id, req.params.linkId]);
  res.status(204).end();
}));

router.post('/events/:id/chat-links', asyncHandler(async (req, res) => {
  const result = await query(
    `
      INSERT INTO calendar_event_chat_links (
        id, event_id, chat_room_id, chat_room_name, source_message_id, source_message_preview, linked_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,now())
      RETURNING *
    `,
    [
      randomUUID(),
      req.params.id,
      req.body.chatRoomId || '',
      emptyToNull(req.body.chatRoomName),
      emptyToNull(req.body.sourceMessageId),
      emptyToNull(req.body.sourceMessagePreview)
    ]
  );
  const item = result.rows[0];
  res.json({
    id: item.id,
    chatRoomId: item.chat_room_id,
    chatRoomName: item.chat_room_name || null,
    sourceMessageId: item.source_message_id || null,
    sourceMessagePreview: item.source_message_preview || null
  });
}));

router.delete('/events/:id/chat-links/:linkId', asyncHandler(async (req, res) => {
  await query('DELETE FROM calendar_event_chat_links WHERE event_id = $1 AND id = $2', [req.params.id, req.params.linkId]);
  res.status(204).end();
}));

router.post('/events/:id/azoom-links', asyncHandler(async (req, res) => {
  const result = await query(
    `
      INSERT INTO calendar_event_azoom_links (
        id, event_id, azoom_meeting_id, azoom_room_id, azoom_join_url,
        azoom_recording_id, azoom_transcript_id, azoom_minutes_id, linked_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,now())
      RETURNING *
    `,
    [
      randomUUID(),
      req.params.id,
      emptyToNull(req.body.azoomMeetingId),
      emptyToNull(req.body.azoomRoomId),
      emptyToNull(req.body.azoomJoinUrl),
      emptyToNull(req.body.azoomRecordingId),
      emptyToNull(req.body.azoomTranscriptId),
      emptyToNull(req.body.azoomMinutesId)
    ]
  );
  const item = result.rows[0];
  res.json({
    id: item.id,
    azoomMeetingId: item.azoom_meeting_id || null,
    azoomRoomId: item.azoom_room_id || null,
    azoomJoinUrl: item.azoom_join_url || null,
    azoomRecordingId: item.azoom_recording_id || null,
    azoomTranscriptId: item.azoom_transcript_id || null,
    azoomMinutesId: item.azoom_minutes_id || null
  });
}));

router.delete('/events/:id/azoom-links/:linkId', asyncHandler(async (req, res) => {
  await query('DELETE FROM calendar_event_azoom_links WHERE event_id = $1 AND id = $2', [req.params.id, req.params.linkId]);
  res.status(204).end();
}));

router.post('/conflicts/check', asyncHandler(async (req, res) => {
  const result = await query(
    `
      SELECT *
      FROM calendar_events
      WHERE deleted_at IS NULL
        AND id <> COALESCE($3::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
        AND start_at < $2::timestamptz
        AND end_at > $1::timestamptz
      ORDER BY start_at ASC
      LIMIT 50
    `,
    [req.body.startAt, req.body.endAt, req.body.excludeEventId || null]
  );
  res.json({
    conflicts: result.rows.map((row) => ({
      eventId: row.id,
      title: row.title,
      startAt: row.start_at,
      endAt: row.end_at,
      reason: 'TIME_OVERLAP',
      ownerName: ''
    }))
  });
}));

router.post('/availability/suggest', asyncHandler(async (req, res) => {
  const start = new Date(req.body.rangeStart || Date.now());
  const duration = Math.max(15, Number(req.body.durationMinutes || 60));
  const suggestions = [];
  for (let index = 0; index < 5; index += 1) {
    const slotStart = new Date(start.getTime() + index * duration * 60 * 1000);
    const slotEnd = new Date(slotStart.getTime() + duration * 60 * 1000);
    suggestions.push({ startAt: slotStart.toISOString(), endAt: slotEnd.toISOString(), score: 100 - index * 10, attendeeConflicts: [] });
  }
  res.json(suggestions);
}));

router.get('/summary/today', asyncHandler(async (req, res) => {
  const result = await query(
    `
      SELECT COUNT(*)::int AS count
      FROM calendar_events
      WHERE deleted_at IS NULL AND start_at::date = now()::date
    `
  );
  res.json({ totalCount: Number(result.rows[0].count || 0), events: [] });
}));

router.get('/summary/week', asyncHandler(async (req, res) => {
  const result = await query(
    `
      SELECT COUNT(*)::int AS count
      FROM calendar_events
      WHERE deleted_at IS NULL AND start_at >= date_trunc('week', now()) AND start_at < date_trunc('week', now()) + interval '7 days'
    `
  );
  res.json({ totalCount: Number(result.rows[0].count || 0), events: [] });
}));

router.get('/search', asyncHandler(async (req, res) => {
  req.query.query = req.query.query || req.query.q || '';
  const result = await query(
    `
      SELECT id, title, start_at, end_at
      FROM calendar_events
      WHERE deleted_at IS NULL AND lower(title) LIKE lower('%' || $1::varchar || '%')
      ORDER BY start_at DESC
      LIMIT 50
    `,
    [req.query.query]
  );
  res.json(result.rows.map((row) => ({ id: row.id, title: row.title, startAt: row.start_at, endAt: row.end_at })));
}));

router.get('/tools', (req, res) => {
  res.json([
    { id: 'create-event', name: 'Create event' },
    { id: 'find-free-time', name: 'Find free time' },
    { id: 'summarize-week', name: 'Summarize week' }
  ]);
});

module.exports = router;
