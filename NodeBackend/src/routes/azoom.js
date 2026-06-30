const fs = require('fs');
const path = require('path');
const express = require('express');
const multer = require('multer');
const { createHmac, randomUUID } = require('crypto');
const config = require('../config');
const { query, tx } = require('../db');
const { asyncHandler, badRequest, notFound } = require('../errors');
const { authRequired } = require('../services/authService');
const { uploadFileName } = require('../utils/uploadNames');
const {
  accountWithProfile,
  effectiveCompany,
  profilesForPrincipal,
  toProfileResponse
} = require('../services/profileService');

function slug(value) {
  return String(value || 'abba-s')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'abba-s';
}

function parseJsonList(value) {
  if (!value) {
    return [];
  }
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.map(String) : [];
  } catch {
    return [];
  }
}

function base64UrlJson(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}

function liveKitEnabled() {
  return Boolean(config.livekit.url && config.livekit.apiKey && config.livekit.apiSecret);
}

function liveKitToken(roomName, principal, profile) {
  if (!liveKitEnabled()) {
    return {
      enabled: false,
      url: '',
      token: '',
      roomName,
      reason: 'LiveKit media server is not configured.'
    };
  }
  const nowSeconds = Math.floor(Date.now() / 1000);
  const displayName = profile && profile.displayName ? profile.displayName : principal.displayName;
  const metadata = {
    userId: principal.userId,
    email: principal.email,
    displayName,
    nickname: profile && profile.nickname ? profile.nickname : displayName,
    avatarColor: profile && profile.avatarColor ? profile.avatarColor : '#7AA06A',
    avatarImageUrl: profile && profile.avatarImageUrl && !String(profile.avatarImageUrl).startsWith('data:')
      ? String(profile.avatarImageUrl).slice(0, 512)
      : ''
  };
  const headerPayload = [
    base64UrlJson({ alg: 'HS256', typ: 'JWT' }),
    base64UrlJson({
      iss: config.livekit.apiKey,
      sub: principal.userId,
      name: displayName,
      metadata: JSON.stringify(metadata),
      nbf: nowSeconds - 10,
      exp: nowSeconds + Math.max(5, config.livekit.tokenMinutes) * 60,
      video: {
        roomJoin: true,
        room: roomName,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true,
        canUpdateOwnMetadata: true
      }
    })
  ].join('.');
  const signature = createHmac('sha256', config.livekit.apiSecret).update(headerPayload).digest('base64url');
  return {
    enabled: true,
    url: config.livekit.url,
    token: `${headerPayload}.${signature}`,
    roomName,
    reason: ''
  };
}

function transcriptTitleTimestamp(date = new Date()) {
  const local = new Date(date.getTime() + 9 * 60 * 60 * 1000);
  return local.toISOString().replace('T', ' ').slice(0, 19);
}

function participantResponse(row) {
  return {
    userId: row.account_id || row.id,
    email: row.email || '',
    displayName: row.display_name || '',
    nickname: row.nickname || row.display_name || '',
    status: row.status || '',
    avatarColor: row.avatar_color || '#7AA06A',
    avatarImageUrl: row.avatar_image_url || '',
    joinedAt: row.joined_at || null,
    muted: Boolean(row.muted),
    deafened: Boolean(row.deafened),
    cameraEnabled: Boolean(row.camera_enabled),
    screenSharing: Boolean(row.screen_sharing)
  };
}

async function participants(channelId) {
  await cleanupStaleVoiceParticipants(channelId);
  const result = await query(
    `
      SELECT p.*, a.email, a.display_name, up.nickname, up.status, up.avatar_color, up.avatar_image_url
      FROM azoom_voice_participants p
      JOIN user_accounts a ON a.id = p.account_id
      LEFT JOIN user_profiles up ON up.account_id = a.id
      WHERE p.channel_id = $1
      ORDER BY p.joined_at ASC
    `,
    [channelId]
  );
  return result.rows.map(participantResponse);
}

async function clearInactiveStartedAt(channelIds) {
  const ids = Array.from(new Set((channelIds || []).filter(Boolean)));
  if (ids.length === 0) {
    return;
  }
  await query(
    `
      UPDATE azoom_voice_channels c
      SET started_at = NULL, updated_at = now()
      WHERE c.id = ANY($1::uuid[])
        AND NOT EXISTS (
          SELECT 1
          FROM azoom_voice_participants p
          WHERE p.channel_id = c.id
        )
    `,
    [ids]
  );
}

async function cleanupStaleVoiceParticipants(channelId = null) {
  const ttlSeconds = Math.max(15, Number(config.azoom.voiceParticipantTtlSeconds || 45));
  const params = [ttlSeconds];
  const scope = channelId ? 'AND channel_id = $2' : '';
  if (channelId) {
    params.push(channelId);
  }
  const removed = await query(
    `
      DELETE FROM azoom_voice_participants
      WHERE updated_at < now() - ($1::int * interval '1 second')
      ${scope}
      RETURNING channel_id
    `,
    params
  );
  await clearInactiveStartedAt(removed.rows.map((row) => row.channel_id));
}

async function channelResponse(row) {
  await cleanupStaleVoiceParticipants(row.id);
  const activeParticipants = await participants(row.id);
  return {
    id: row.id,
    name: row.name,
    roomName: row.room_name,
    startedAt: activeParticipants.length > 0 ? row.started_at || null : null,
    serverNow: new Date().toISOString(),
    accessMode: row.access_mode || 'ALL',
    allowedDepartments: parseJsonList(row.allowed_departments_json),
    canJoin: true,
    participants: activeParticipants
  };
}

async function ensureDefaultChannel(companyName) {
  const existing = await query(
    `
      SELECT *
      FROM azoom_voice_channels
      WHERE company_name = $1 AND archived_at IS NULL
      ORDER BY created_at ASC
      LIMIT 1
    `,
    [companyName]
  );
  if (existing.rows[0]) {
    return existing.rows[0];
  }
  const id = randomUUID();
  const result = await query(
    `
      INSERT INTO azoom_voice_channels (
        id, company_name, name, room_name, started_at, access_mode,
        allowed_departments_json, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, NULL, 'ALL', '[]', now(), now())
      RETURNING *
    `,
    [id, companyName, `${companyName} Voice`, `azoom-${slug(companyName)}-${id.slice(0, 8)}`]
  );
  return result.rows[0];
}

async function channelById(channelId, principal, req) {
  const companyName = await effectiveCompany(principal, req);
  await ensureDefaultChannel(companyName);
  const result = await query(
    'SELECT * FROM azoom_voice_channels WHERE id = $1 AND company_name = $2 AND archived_at IS NULL',
    [channelId, companyName]
  );
  if (!result.rows[0]) {
    throw notFound('AZOOM voice channel not found.');
  }
  return result.rows[0];
}

async function allChannelResponses(principal, req) {
  const companyName = await effectiveCompany(principal, req);
  await ensureDefaultChannel(companyName);
  await cleanupStaleVoiceParticipants();
  const result = await query(
    `
      SELECT *
      FROM azoom_voice_channels
      WHERE company_name = $1 AND archived_at IS NULL
      ORDER BY created_at ASC
    `,
    [companyName]
  );
  const responses = [];
  for (const row of result.rows) {
    responses.push(await channelResponse(row));
  }
  return responses;
}

async function publishVoiceStates(realtimeHub, principal, req) {
  const channels = await allChannelResponses(principal, req);
  for (const channel of channels) {
    realtimeHub.publish(`/topic/azoom/voice/${channel.roomName}`, channel);
  }
}

function meetingSummary(row, utteranceCount = 0) {
  return {
    id: row.id,
    channelId: row.channel_id || '',
    channelName: row.channel_name || '',
    roomName: row.room_name || '',
    kind: row.kind || 'REALTIME',
    status: row.status || 'READY',
    titleTimestamp: row.title_timestamp || '',
    startedAt: row.started_at || null,
    endedAt: row.ended_at || null,
    utteranceCount: Number(utteranceCount || 0)
  };
}

function utteranceResponse(row) {
  return {
    id: row.id,
    sequenceNo: Number(row.sequence_no || 0),
    speakerUserId: row.speaker_user_id || '',
    speakerName: row.speaker_name || '',
    speakerEmail: row.speaker_email || '',
    content: row.content || '',
    startedAt: row.started_at || row.created_at || null,
    endedAt: row.ended_at || row.created_at || null
  };
}

async function transcriptResponse(transcriptId) {
  const transcript = await query('SELECT * FROM azoom_meeting_transcripts WHERE id = $1', [transcriptId]);
  if (!transcript.rows[0]) {
    throw notFound('Meeting transcript not found.');
  }
  const utterances = await query(
    'SELECT * FROM azoom_meeting_utterances WHERE transcript_id = $1 ORDER BY sequence_no ASC',
    [transcriptId]
  );
  const row = transcript.rows[0];
  return {
    id: row.id,
    companyName: row.company_name || '',
    companySlug: row.company_slug || '',
    channelId: row.channel_id || '',
    channelName: row.channel_name || '',
    roomName: row.room_name || '',
    kind: row.kind || 'REALTIME',
    status: row.status || 'READY',
    titleTimestamp: row.title_timestamp || '',
    audioFilePath: row.audio_file_path || '',
    startedAt: row.started_at || null,
    endedAt: row.ended_at || null,
    utterances: utterances.rows.map(utteranceResponse)
  };
}

async function activeTranscript(channel, principal, req) {
  const companyName = await effectiveCompany(principal, req);
  const existing = await query(
    `
      SELECT *
      FROM azoom_meeting_transcripts
      WHERE channel_id = $1 AND kind = 'REALTIME' AND ended_at IS NULL
      ORDER BY started_at DESC
      LIMIT 1
    `,
    [channel.id]
  );
  if (existing.rows[0]) {
    return existing.rows[0];
  }
  const result = await query(
    `
      INSERT INTO azoom_meeting_transcripts (
        id, company_name, company_slug, channel_id, channel_name, room_name,
        kind, status, title_timestamp, started_at, created_by, created_at, updated_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,'REALTIME','READY',$7,now(),$8,now(),now())
      RETURNING *
    `,
    [
      randomUUID(),
      companyName,
      slug(companyName),
      channel.id,
      channel.name,
      channel.room_name,
      transcriptTitleTimestamp(),
      principal.userId
    ]
  );
  return result.rows[0];
}

async function appendUtterance(transcriptId, body, principal) {
  const sequence = await query(
    'SELECT COALESCE(MAX(sequence_no), 0)::int + 1 AS next FROM azoom_meeting_utterances WHERE transcript_id = $1',
    [transcriptId]
  );
  await query(
    `
      INSERT INTO azoom_meeting_utterances (
        id, transcript_id, sequence_no, speaker_user_id, speaker_name, speaker_email,
        content, started_at, ended_at, created_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,now())
    `,
    [
      randomUUID(),
      transcriptId,
      Number(sequence.rows[0].next || 1),
      body.speakerUserId || principal.userId,
      body.speakerName || principal.displayName || '',
      body.speakerEmail || principal.email || '',
      String(body.content || body.text || '').slice(0, 20000),
      body.startedAt || new Date().toISOString(),
      body.endedAt || new Date().toISOString()
    ]
  );
  await query('UPDATE azoom_meeting_transcripts SET updated_at = now() WHERE id = $1', [transcriptId]);
  return transcriptResponse(transcriptId);
}

function createAzoomRouter(realtimeHub) {
  const router = express.Router();
  const audioDir = path.join(config.backendDir, 'NotivaAudio');
  fs.mkdirSync(audioDir, { recursive: true });
  const upload = multer({ dest: audioDir });

  router.use(authRequired);

  router.get('/channels', asyncHandler(async (req, res) => {
    const companyName = await effectiveCompany(req.principal, req);
    const voiceChannels = await allChannelResponses(req.principal, req);
    res.json({
      companyName,
      liveKitEnabled: liveKitEnabled(),
      liveKitUrl: liveKitEnabled() ? config.livekit.url : '',
      voiceChannels
    });
  }));

  router.get('/workspace', asyncHandler(async (req, res) => {
    const companyName = await effectiveCompany(req.principal, req);
    const profiles = await profilesForPrincipal(req.principal);
    res.json({
      id: `workspace-${slug(companyName)}`,
      companyName,
      companySlug: slug(companyName),
      name: `${companyName} AZOOM`,
      members: profiles.map((profile) => ({
        accountId: profile.id,
        email: profile.email,
        displayName: profile.displayName,
        role: profile.role === 'SUPERUSER' || profile.role === 'ADMIN' ? 'ADMIN' : 'MEMBER'
      }))
    });
  }));

  router.get('/invite-candidates', asyncHandler(async (req, res) => {
    const profiles = await profilesForPrincipal(req.principal);
    res.json(profiles.map((profile) => ({
      accountId: profile.id,
      email: profile.email,
      displayName: profile.displayName,
      department: profile.department || '',
      position: profile.position || '',
      avatarColor: profile.avatarColor || '#7AA06A',
      avatarImageUrl: profile.avatarImageUrl || ''
    })));
  }));

  router.post('/invite-members', asyncHandler(async (req, res) => {
    const companyName = await effectiveCompany(req.principal, req);
    const accountIds = Array.isArray(req.body.accountIds) ? req.body.accountIds.map(String) : [];
    for (const accountId of accountIds) {
      await accountWithProfile(accountId);
    }
    const profiles = await profilesForPrincipal(req.principal);
    res.json({
      id: `workspace-${slug(companyName)}`,
      companyName,
      companySlug: slug(companyName),
      name: `${companyName} AZOOM`,
      members: profiles.map((profile) => ({
        accountId: profile.id,
        email: profile.email,
        displayName: profile.displayName,
        role: profile.role === 'SUPERUSER' || profile.role === 'ADMIN' ? 'ADMIN' : 'MEMBER'
      }))
    });
  }));

  router.post('/voice-channels', asyncHandler(async (req, res) => {
    const companyName = await effectiveCompany(req.principal, req);
    const id = randomUUID();
    const name = String(req.body.name || 'Voice channel').trim().slice(0, 120);
    const result = await query(
      `
        INSERT INTO azoom_voice_channels (
          id, company_name, name, room_name, access_mode, allowed_departments_json,
          created_at, updated_at
        )
        VALUES ($1,$2,$3,$4,$5,$6,now(),now())
        RETURNING *
      `,
      [
        id,
        companyName,
        name,
        `azoom-${slug(companyName)}-${id.slice(0, 8)}`,
        req.body.accessMode || 'ALL',
        JSON.stringify(Array.isArray(req.body.allowedDepartments) ? req.body.allowedDepartments : [])
      ]
    );
    res.json(await channelResponse(result.rows[0]));
  }));

  router.put('/voice-channels/:channelId', asyncHandler(async (req, res) => {
    const channel = await channelById(req.params.channelId, req.principal, req);
    const result = await query(
      `
        UPDATE azoom_voice_channels
        SET name = COALESCE($2, name),
            access_mode = COALESCE($3, access_mode),
            allowed_departments_json = COALESCE($4, allowed_departments_json),
            updated_at = now()
        WHERE id = $1
        RETURNING *
      `,
      [
        channel.id,
        req.body.name ? String(req.body.name).slice(0, 120) : null,
        req.body.accessMode || null,
        Array.isArray(req.body.allowedDepartments) ? JSON.stringify(req.body.allowedDepartments) : null
      ]
    );
    const response = await channelResponse(result.rows[0]);
    realtimeHub.publish(`/topic/azoom/voice/${response.roomName}`, response);
    res.json(response);
  }));

  router.delete('/channels/:channelId', asyncHandler(async (req, res) => {
    await channelById(req.params.channelId, req.principal, req);
    await query('UPDATE azoom_voice_channels SET archived_at = now(), updated_at = now() WHERE id = $1', [req.params.channelId]);
    res.json({
      companyName: await effectiveCompany(req.principal, req),
      liveKitEnabled: liveKitEnabled(),
      liveKitUrl: liveKitEnabled() ? config.livekit.url : '',
      voiceChannels: await allChannelResponses(req.principal, req)
    });
  }));

  router.put('/voice-channels/:channelId/access', asyncHandler(async (req, res) => {
    await channelById(req.params.channelId, req.principal, req);
    const result = await query(
      `
        UPDATE azoom_voice_channels
        SET access_mode = $2,
            allowed_departments_json = $3,
            updated_at = now()
        WHERE id = $1
        RETURNING *
      `,
      [
        req.params.channelId,
        req.body.accessMode || 'ALL',
        JSON.stringify(Array.isArray(req.body.allowedDepartments) ? req.body.allowedDepartments : [])
      ]
    );
    const response = await channelResponse(result.rows[0]);
    await publishVoiceStates(realtimeHub, req.principal, req);
    res.json(response);
  }));

  router.get('/voice-channels/:channelId/state', asyncHandler(async (req, res) => {
    res.json(await channelResponse(await channelById(req.params.channelId, req.principal, req)));
  }));

  router.post('/voice-channels/:channelId/join', asyncHandler(async (req, res) => {
    const channel = await channelById(req.params.channelId, req.principal, req);
    const profileRow = await accountWithProfile(req.principal.userId);
    const profile = toProfileResponse(profileRow);
    await tx(async (client) => {
      await client.query(
        `
          UPDATE azoom_voice_channels
          SET started_at = COALESCE(started_at, now()), updated_at = now()
          WHERE id = $1
        `,
        [channel.id]
      );
      await client.query(
        `
          INSERT INTO azoom_voice_participants (
            id, channel_id, account_id, muted, deafened, camera_enabled,
            screen_sharing, joined_at, updated_at
          )
          VALUES ($1,$2,$3,false,false,false,false,now(),now())
          ON CONFLICT (channel_id, account_id)
          DO UPDATE SET updated_at = now()
        `,
        [randomUUID(), channel.id, req.principal.userId]
      );
    });
    const refreshed = await channelById(req.params.channelId, req.principal, req);
    const response = await channelResponse(refreshed);
    await publishVoiceStates(realtimeHub, req.principal, req);
    res.json({ channel: response, liveKit: liveKitToken(refreshed.room_name, req.principal, profile) });
  }));

  router.post('/voice-channels/:channelId/leave', asyncHandler(async (req, res) => {
    const channel = await channelById(req.params.channelId, req.principal, req);
    await query(
      'DELETE FROM azoom_voice_participants WHERE channel_id = $1 AND account_id = $2',
      [channel.id, req.principal.userId]
    );
    await clearInactiveStartedAt([channel.id]);
    const refreshed = await channelById(req.params.channelId, req.principal, req);
    const response = await channelResponse(refreshed);
    await publishVoiceStates(realtimeHub, req.principal, req);
    res.json(response);
  }));

  router.put('/voice-channels/:channelId/status', asyncHandler(async (req, res) => {
    const channel = await channelById(req.params.channelId, req.principal, req);
    await query(
      `
        UPDATE azoom_voice_participants
        SET muted = COALESCE($3, muted),
            deafened = COALESCE($4, deafened),
            camera_enabled = COALESCE($5, camera_enabled),
            screen_sharing = COALESCE($6, screen_sharing),
            updated_at = now()
        WHERE channel_id = $1 AND account_id = $2
      `,
      [
        channel.id,
        req.principal.userId,
        typeof req.body.muted === 'boolean' ? req.body.muted : null,
        typeof req.body.deafened === 'boolean' ? req.body.deafened : null,
        typeof req.body.cameraEnabled === 'boolean' ? req.body.cameraEnabled : null,
        typeof req.body.screenSharing === 'boolean' ? req.body.screenSharing : null
      ]
    );
    const response = await channelResponse(channel);
    await publishVoiceStates(realtimeHub, req.principal, req);
    res.json(response);
  }));

  router.get('/voice-channels/:channelId/livekit-token', asyncHandler(async (req, res) => {
    const channel = await channelById(req.params.channelId, req.principal, req);
    const profile = toProfileResponse(await accountWithProfile(req.principal.userId));
    res.json(liveKitToken(channel.room_name, req.principal, profile));
  }));

  router.post('/voice-channels/:channelId/effects/firework', asyncHandler(async (req, res) => {
    const channel = await channelById(req.params.channelId, req.principal, req);
    const response = {
      type: 'FIREWORK',
      channelId: channel.id,
      roomName: channel.room_name,
      senderUserId: req.principal.userId,
      occurredAt: new Date().toISOString()
    };
    realtimeHub.publish(`/topic/azoom/voice-effects/${channel.room_name}`, response);
    res.json(response);
  }));

  router.get('/meeting-transcripts', asyncHandler(async (req, res) => {
    const companyName = await effectiveCompany(req.principal, req);
    const result = await query(
      `
        SELECT t.*, COUNT(u.id)::int AS utterance_count
        FROM azoom_meeting_transcripts t
        LEFT JOIN azoom_meeting_utterances u ON u.transcript_id = t.id
        WHERE t.company_name = $1
        GROUP BY t.id
        ORDER BY t.started_at DESC
        LIMIT 100
      `,
      [companyName]
    );
    res.json(result.rows.map((row) => meetingSummary(row, row.utterance_count)));
  }));

  router.get('/meeting-transcripts/:transcriptId', asyncHandler(async (req, res) => {
    res.json(await transcriptResponse(req.params.transcriptId));
  }));

  router.post('/voice-channels/:channelId/notiva/start', asyncHandler(async (req, res) => {
    const channel = await channelById(req.params.channelId, req.principal, req);
    const transcript = await activeTranscript(channel, req.principal, req);
    const realtimeTranscript = await transcriptResponse(transcript.id);
    const response = { roomName: channel.room_name, realtimeTranscript };
    realtimeHub.publish(`/topic/azoom/notiva/${channel.room_name}`, {
      type: 'STARTED',
      roomName: channel.room_name,
      transcript: realtimeTranscript
    });
    res.json(response);
  }));

  router.post('/voice-channels/:channelId/notiva/realtime-utterances', asyncHandler(async (req, res) => {
    const channel = await channelById(req.params.channelId, req.principal, req);
    const transcript = await activeTranscript(channel, req.principal, req);
    const response = await appendUtterance(transcript.id, req.body, req.principal);
    realtimeHub.publish(`/topic/azoom/notiva/${channel.room_name}`, {
      type: 'REALTIME_UTTERANCE',
      roomName: channel.room_name,
      transcript: response
    });
    res.json(response);
  }));

  router.post('/voice-channels/:channelId/notiva/finish', asyncHandler(async (req, res) => {
    const channel = await channelById(req.params.channelId, req.principal, req);
    const current = await query(
      `
        UPDATE azoom_meeting_transcripts
        SET ended_at = COALESCE(ended_at, now()), status = 'READY', updated_at = now()
        WHERE id = (
          SELECT id FROM azoom_meeting_transcripts
          WHERE channel_id = $1 AND kind = 'REALTIME'
          ORDER BY started_at DESC
          LIMIT 1
        )
        RETURNING id
      `,
      [channel.id]
    );
    if (!current.rows[0]) {
      throw notFound('Active Notiva transcript not found.');
    }
    const response = await transcriptResponse(current.rows[0].id);
    realtimeHub.publish(`/topic/azoom/notiva/${channel.room_name}`, {
      type: 'FINISHED',
      roomName: channel.room_name,
      transcript: response
    });
    res.json(response);
  }));

  async function handleAudio(req, res, type) {
    const channel = await channelById(req.params.channelId, req.principal, req);
    if (!req.file) {
      throw badRequest('Audio file is required.');
    }
    const transcript = await activeTranscript(channel, req.principal, req);
    const sourceFileName = uploadFileName(req.file, req.file.filename);
    const content = `${type === 'batch' ? 'Batch' : 'Realtime'} audio uploaded: ${sourceFileName}`;
    const response = await appendUtterance(transcript.id, {
      content,
      speakerUserId: req.body.speakerUserId,
      speakerName: req.body.speakerName,
      speakerEmail: req.body.speakerEmail
    }, req.principal);
    await query(
      'UPDATE azoom_meeting_transcripts SET audio_file_path = COALESCE(audio_file_path, $2), updated_at = now() WHERE id = $1',
      [transcript.id, req.file.path]
    );
    realtimeHub.publish(`/topic/azoom/notiva/${channel.room_name}`, {
      type: type === 'batch' ? 'BATCH_AUDIO' : 'REALTIME_AUDIO',
      roomName: channel.room_name,
      transcript: response
    });
    res.json({ sourceFileName, transcript: response });
  }

  router.post('/voice-channels/:channelId/notiva/realtime-audio', upload.single('file'), asyncHandler((req, res) => handleAudio(req, res, 'realtime')));
  router.post('/voice-channels/:channelId/notiva/batch-audio', upload.single('file'), asyncHandler((req, res) => handleAudio(req, res, 'batch')));

  return router;
}

module.exports = {
  createAzoomRouter
};
