const { randomUUID } = require('crypto');
const { query, tx } = require('../db');
const { badRequest, forbidden, notFound } = require('../errors');
const {
  accountWithProfile,
  effectiveCompany,
  normalizeCompany,
  toProfileResponse
} = require('./profileService');
const { repairLatin1Utf8FileName } = require('../utils/uploadNames');

function trim(value) {
  return value == null ? '' : String(value).trim();
}

function limit(value, max) {
  const text = trim(value);
  return text.length > max ? text.slice(0, max) : text;
}

function parseJsonList(value) {
  if (!value) {
    return [];
  }
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function mentionsFromMessage(row) {
  const ids = row.mention_user_ids ? String(row.mention_user_ids).split(',').map(trim).filter(Boolean) : [];
  const names = row.mention_display_names ? String(row.mention_display_names).split('\n') : [];
  return ids.map((id, index) => ({
    userId: id,
    displayName: names[index] || ''
  }));
}

function attachmentFromMessage(row) {
  if (!row.attachment_id || row.deleted_for_everyone) {
    return null;
  }
  return {
    id: row.attachment_id,
    fileName: repairLatin1Utf8FileName(row.attachment_file_name),
    contentType: row.attachment_content_type,
    size: Number(row.attachment_size || 0),
    downloadUrl: `/api/chat/rooms/${row.room_code}/attachments/${row.attachment_id}`,
    groupId: row.attachment_group_id || null
  };
}

function messageResponse(row, unreadCount = 0, senderProfile = null) {
  const attachment = attachmentFromMessage(row);
  return {
    id: String(row.id),
    roomCode: row.room_code,
    senderId: row.sender_id,
    senderName: row.sender_name,
    senderNickname: senderProfile ? senderProfile.nickname || '' : row.sender_nickname || '',
    senderAvatarColor: senderProfile ? senderProfile.avatarColor || '#7AA06A' : row.sender_avatar_color || '#7AA06A',
    senderAvatarImageUrl: senderProfile ? senderProfile.avatarImageUrl || '' : row.sender_avatar_image_url || '',
    content: attachment ? attachment.fileName : row.content,
    sentAt: row.sent_at,
    unreadCount,
    systemMessage: Boolean(row.system_message),
    silent: Boolean(row.silent_message),
    spoiler: Boolean(row.spoiler_message),
    deletedForEveryone: Boolean(row.deleted_for_everyone),
    attachment,
    mentions: row.deleted_for_everyone ? [] : mentionsFromMessage(row)
  };
}

function noticeResponse(room) {
  if (!room.notice_content) {
    return null;
  }
  return {
    messageId: room.notice_message_id,
    senderId: room.notice_sender_id,
    senderName: room.notice_sender_name,
    content: room.notice_content,
    sentAt: room.notice_sent_at
  };
}

class ChatService {
  constructor(realtimeHub) {
    this.realtimeHub = realtimeHub;
  }

  async rooms(principal, req = null) {
    const companyName = await effectiveCompany(principal, req);
    const pinnedOrder = await this.pinnedRoomOrder(principal.userId);
    const result = await query(
      `
        SELECT r.*
        FROM chat_rooms r
        WHERE COALESCE(r.company_name, 'ABBA-S') = $2
          AND NOT (r.code LIKE 'azoom-%' OR r.code LIKE 'azoom:%' OR r.code LIKE 'azoom_%')
          AND (
            EXISTS (
              SELECT 1 FROM chat_room_members m
              WHERE m.room_id = r.id AND m.account_id = $1
            )
            OR ($3 = 'SUPERUSER' AND r.type = 'GROUP')
          )
          AND (
            r.type = 'SELF'
            OR COALESCE(r.last_message, '') <> ''
            OR r.created_by_account_id = $1
            OR r.pinned_default = true
          )
        ORDER BY r.last_message_at DESC
      `,
      [principal.userId, companyName, principal.role]
    );
    const roomCodes = result.rows.map((room) => room.code);
    const [membersByRoom, unreadCounts, mentionedRooms] = await Promise.all([
      this.membersByRoomCodes(roomCodes),
      this.unreadRoomCounts(roomCodes, principal.userId),
      this.unreadMentionedRooms(roomCodes, principal.userId)
    ]);
    const responses = result.rows.map((room) => this.buildRoomResponse(
      room,
      membersByRoom.get(room.code) || [],
      pinnedOrder,
      unreadCounts.get(room.code) || 0,
      mentionedRooms.has(room.code)
    ));
    return responses.sort((left, right) => {
      if (left.pinned !== right.pinned) {
        return left.pinned ? -1 : 1;
      }
      const leftTime = new Date(left.pinnedAt || left.lastMessageAt || 0).getTime();
      const rightTime = new Date(right.pinnedAt || right.lastMessageAt || 0).getTime();
      return rightTime - leftTime;
    });
  }

  buildRoomResponse(room, members, pinnedOrder, unreadCount, mentioned) {
    const order = pinnedOrder || new Map();
    const pinned = order.has(room.code) || Boolean(room.pinned_default);
    const pinnedAt = order.get(room.code) || room.pinned_at || null;
    return {
      code: room.code,
      title: room.title,
      type: room.type,
      participantCount: members.length,
      pinned,
      pinnedAt: pinned ? pinnedAt : null,
      lastMessage: room.last_message || '',
      lastMessageAt: room.last_message_at,
      lastMessageSpoiler: Boolean(room.last_message_spoiler),
      avatarImageUrl: room.avatar_image_url || null,
      notice: noticeResponse(room),
      members,
      unreadCount: Number(unreadCount || 0),
      mentioned: Boolean(mentioned)
    };
  }

  async pinnedRoomOrder(accountId) {
    const result = await query(
      'SELECT pinned_room_ids_json FROM user_chat_folder_settings WHERE account_id = $1',
      [accountId]
    );
    const ids = parseJsonList(result.rows[0] && result.rows[0].pinned_room_ids_json);
    const now = Date.now();
    const order = new Map();
    ids.forEach((id, index) => order.set(id, new Date(now - index).toISOString()));
    return order;
  }

  async pinnedRoomOrders(accountIds) {
    const uniqueIds = Array.from(new Set((accountIds || []).filter(Boolean)));
    const orders = new Map(uniqueIds.map((id) => [id, new Map()]));
    if (uniqueIds.length === 0) {
      return orders;
    }
    const result = await query(
      'SELECT account_id, pinned_room_ids_json FROM user_chat_folder_settings WHERE account_id = ANY($1::uuid[])',
      [uniqueIds]
    );
    const now = Date.now();
    for (const row of result.rows) {
      const order = new Map();
      parseJsonList(row.pinned_room_ids_json).forEach((id, index) => {
        order.set(id, new Date(now - index).toISOString());
      });
      orders.set(row.account_id, order);
    }
    return orders;
  }

  async members(roomCode) {
    const result = await query(
      `
        SELECT
          a.id, a.email, a.display_name, a.role,
          p.department, p.company_name, p.position, p.nickname, p.phone_number,
          p.contact_email, p.gender, p.birth_date, p.status, p.presence_updated_at,
          p.avatar_color, p.status_message, p.avatar_image_url,
          p.profile_background_color, p.profile_background_image_url
        FROM chat_room_members m
        JOIN chat_rooms r ON r.id = m.room_id
        JOIN user_accounts a ON a.id = m.account_id
        LEFT JOIN user_profiles p ON p.account_id = a.id
        WHERE r.code = $1
        ORDER BY m.joined_at ASC
      `,
      [roomCode]
    );
    return result.rows.map((row) => toProfileResponse(row));
  }

  async membersByRoomCodes(roomCodes) {
    const uniqueCodes = Array.from(new Set((roomCodes || []).filter(Boolean)));
    const grouped = new Map(uniqueCodes.map((code) => [code, []]));
    if (uniqueCodes.length === 0) {
      return grouped;
    }
    const result = await query(
      `
        SELECT
          r.code AS room_code,
          a.id, a.email, a.display_name, a.role,
          p.department, p.company_name, p.position, p.nickname, p.phone_number,
          p.contact_email, p.gender, p.birth_date, p.status, p.presence_updated_at,
          p.avatar_color, p.status_message, p.avatar_image_url,
          p.profile_background_color, p.profile_background_image_url
        FROM chat_room_members m
        JOIN chat_rooms r ON r.id = m.room_id
        JOIN user_accounts a ON a.id = m.account_id
        LEFT JOIN user_profiles p ON p.account_id = a.id
        WHERE r.code = ANY($1::text[])
        ORDER BY r.code ASC, m.joined_at ASC
      `,
      [uniqueCodes]
    );
    for (const row of result.rows) {
      const members = grouped.get(row.room_code) || [];
      members.push(toProfileResponse(row));
      grouped.set(row.room_code, members);
    }
    return grouped;
  }

  async findRoom(roomCode) {
    const result = await query('SELECT * FROM chat_rooms WHERE code = $1', [roomCode]);
    return result.rows[0] || null;
  }

  async roomForMember(roomCode, accountId) {
    const account = await accountWithProfile(accountId);
    if (!account) {
      throw notFound('Account not found.');
    }
    const room = await this.findRoom(roomCode);
    if (!room) {
      throw notFound('Chat room not found.');
    }
    return this.roomResponse(room, {
      userId: account.id,
      email: account.email,
      displayName: account.display_name,
      role: account.role,
      sessionId: ''
    });
  }

  async roomResponse(room, principal, pinnedOrder = null, precomputed = {}) {
    const members = precomputed.members || await this.members(room.code);
    const order = pinnedOrder || precomputed.pinnedOrder || await this.pinnedRoomOrder(principal.userId);
    const unreadCount = precomputed.unreadCount != null
      ? precomputed.unreadCount
      : await this.unreadRoomCount(room.code, principal.userId);
    const mentioned = precomputed.mentioned != null
      ? precomputed.mentioned
      : await this.unreadMentioned(room.code, principal.userId);
    return this.buildRoomResponse(room, members, order, unreadCount, mentioned);
  }

  async unreadRoomCount(roomCode, accountId) {
    const result = await query(
      `
        SELECT COUNT(*)::int AS count
        FROM chat_message_records msg
        JOIN chat_rooms r ON r.code = msg.room_code
        LEFT JOIN chat_room_members m ON m.room_id = r.id AND m.account_id = $2
        WHERE msg.room_code = $1
          AND msg.sender_id <> $2
          AND (m.joined_at IS NULL OR msg.sent_at >= m.joined_at)
          AND NOT EXISTS (
            SELECT 1 FROM chat_message_read_receipts rr
            WHERE rr.message_id = msg.id AND rr.account_id = $2
          )
      `,
      [roomCode, accountId]
    );
    return result.rows[0] ? Number(result.rows[0].count) : 0;
  }

  async unreadRoomCounts(roomCodes, accountId) {
    const uniqueCodes = Array.from(new Set((roomCodes || []).filter(Boolean)));
    const counts = new Map(uniqueCodes.map((code) => [code, 0]));
    if (uniqueCodes.length === 0) {
      return counts;
    }
    const result = await query(
      `
        SELECT msg.room_code, COUNT(*)::int AS count
        FROM chat_message_records msg
        JOIN chat_rooms r ON r.code = msg.room_code
        LEFT JOIN chat_room_members m ON m.room_id = r.id AND m.account_id = $2
        LEFT JOIN chat_message_read_receipts rr ON rr.message_id = msg.id AND rr.account_id = $2
        WHERE msg.room_code = ANY($1::text[])
          AND msg.sender_id <> $2
          AND (m.joined_at IS NULL OR msg.sent_at >= m.joined_at)
          AND rr.message_id IS NULL
        GROUP BY msg.room_code
      `,
      [uniqueCodes, accountId]
    );
    for (const row of result.rows) {
      counts.set(row.room_code, Number(row.count || 0));
    }
    return counts;
  }

  async unreadRoomCountsForAccounts(roomCode, accountIds) {
    const uniqueIds = Array.from(new Set((accountIds || []).filter(Boolean)));
    const counts = new Map(uniqueIds.map((id) => [id, 0]));
    if (uniqueIds.length === 0) {
      return counts;
    }
    const result = await query(
      `
        SELECT m.account_id, COUNT(msg.id) FILTER (WHERE rr.message_id IS NULL)::int AS count
        FROM chat_room_members m
        JOIN chat_rooms r ON r.id = m.room_id
        LEFT JOIN chat_message_records msg
          ON msg.room_code = r.code
         AND msg.sender_id <> m.account_id
         AND msg.sent_at >= m.joined_at
        LEFT JOIN chat_message_read_receipts rr ON rr.message_id = msg.id AND rr.account_id = m.account_id
        WHERE r.code = $1 AND m.account_id = ANY($2::uuid[])
        GROUP BY m.account_id
      `,
      [roomCode, uniqueIds]
    );
    for (const row of result.rows) {
      counts.set(row.account_id, Number(row.count || 0));
    }
    return counts;
  }

  async unreadMentioned(roomCode, accountId) {
    const result = await query(
      `
        SELECT COUNT(*)::int AS count
        FROM chat_mention_notifications
        WHERE room_code = $1 AND mentioned_account_id = $2 AND checked_at IS NULL
      `,
      [roomCode, accountId]
    );
    return result.rows[0] && Number(result.rows[0].count) > 0;
  }

  async unreadMentionedRooms(roomCodes, accountId) {
    const uniqueCodes = Array.from(new Set((roomCodes || []).filter(Boolean)));
    if (uniqueCodes.length === 0) {
      return new Set();
    }
    const result = await query(
      `
        SELECT room_code
        FROM chat_mention_notifications
        WHERE room_code = ANY($1::text[])
          AND mentioned_account_id = $2
          AND checked_at IS NULL
        GROUP BY room_code
      `,
      [uniqueCodes, accountId]
    );
    return new Set(result.rows.map((row) => row.room_code));
  }

  async unreadMentionedAccounts(roomCode, accountIds) {
    const uniqueIds = Array.from(new Set((accountIds || []).filter(Boolean)));
    if (uniqueIds.length === 0) {
      return new Set();
    }
    const result = await query(
      `
        SELECT mentioned_account_id
        FROM chat_mention_notifications
        WHERE room_code = $1
          AND mentioned_account_id = ANY($2::uuid[])
          AND checked_at IS NULL
        GROUP BY mentioned_account_id
      `,
      [roomCode, uniqueIds]
    );
    return new Set(result.rows.map((row) => row.mentioned_account_id));
  }

  async roomResponsesForMembers(room, members = null) {
    const roomMembers = members || await this.members(room.code);
    const accountIds = roomMembers.map((member) => member.id);
    const [pinnedOrders, unreadCounts, mentionedAccounts] = await Promise.all([
      this.pinnedRoomOrders(accountIds),
      this.unreadRoomCountsForAccounts(room.code, accountIds),
      this.unreadMentionedAccounts(room.code, accountIds)
    ]);
    const responses = new Map();
    for (const member of roomMembers) {
      responses.set(member.id, this.buildRoomResponse(
        room,
        roomMembers,
        pinnedOrders.get(member.id) || new Map(),
        unreadCounts.get(member.id) || 0,
        mentionedAccounts.has(member.id)
      ));
    }
    return responses;
  }

  async assertMember(roomCode, principal) {
    const result = await query(
      `
        SELECT m.*
        FROM chat_room_members m
        JOIN chat_rooms r ON r.id = m.room_id
        WHERE r.code = $1 AND m.account_id = $2
      `,
      [roomCode, principal.userId]
    );
    if (result.rows[0]) {
      return result.rows[0];
    }
    const room = await this.findRoom(roomCode);
    if (room && principal.role === 'SUPERUSER' && room.type === 'GROUP') {
      return null;
    }
    throw forbidden('Chat room permission is required.');
  }

  async startDirectRoom(request, principal, req = null) {
    const target = await this.findDirectTarget(request);
    if (!target) {
      throw notFound('Direct chat target not found.');
    }
    if (target.id === principal.userId) {
      throw badRequest('Cannot start a direct room with yourself.');
    }
    const companyName = await effectiveCompany(principal, req);
    if (normalizeCompany(target.company_name) !== companyName) {
      throw forbidden('Chat target must belong to the same company.');
    }
    const existing = await query(
      `
        SELECT r.*
        FROM chat_rooms r
        JOIN chat_room_members a ON a.room_id = r.id AND a.account_id = $1
        JOIN chat_room_members b ON b.room_id = r.id AND b.account_id = $2
        WHERE r.type = 'DIRECT' AND COALESCE(r.company_name, 'ABBA-S') = $3
        LIMIT 1
      `,
      [principal.userId, target.id, companyName]
    );
    if (existing.rows[0]) {
      return this.roomResponse(existing.rows[0], principal);
    }
    const current = await accountWithProfile(principal.userId);
    const room = await tx(async (client) => {
      const roomResult = await client.query(
        `
          INSERT INTO chat_rooms (
            id, code, title, company_name, type, pinned_default, last_message,
            last_message_at, created_by_account_id, created_at
          )
          VALUES ($1, $2, $3, $4, 'DIRECT', false, '', now(), $5, now())
          RETURNING *
        `,
        [randomUUID(), `direct-${randomUUID()}`, target.display_name, companyName, principal.userId]
      );
      await this.ensureMember(client, roomResult.rows[0].id, principal.userId);
      await this.ensureMember(client, roomResult.rows[0].id, target.id);
      return roomResult.rows[0];
    });
    const response = await this.roomResponse(room, principal);
    await this.publishRoomState(response);
    await this.publishRoomState(await this.roomResponse(room, {
      userId: target.id,
      email: target.email,
      displayName: target.display_name,
      role: target.role,
      sessionId: ''
    }));
    return response;
  }

  async findDirectTarget(request) {
    if (request.targetUserId) {
      return accountWithProfile(request.targetUserId);
    }
    if (request.targetEmail) {
      const result = await query(
        `
          SELECT
            a.id, a.email, a.display_name, a.role, a.enabled,
            p.company_name, p.nickname, p.avatar_color, p.avatar_image_url
          FROM user_accounts a
          LEFT JOIN user_profiles p ON p.account_id = a.id
          WHERE lower(a.email) = lower($1)
        `,
        [request.targetEmail]
      );
      return result.rows[0] || null;
    }
    throw badRequest('Direct chat target is required.');
  }

  async startGroupRoom(request, principal, req = null) {
    const targetUserIds = Array.from(new Set((request.targetUserIds || []).map(String))).filter((id) => id !== principal.userId);
    if (targetUserIds.length === 0) {
      throw badRequest('Group chat needs at least one participant.');
    }
    const companyName = await effectiveCompany(principal, req);
    const targets = [];
    for (const targetId of targetUserIds) {
      const account = await accountWithProfile(targetId);
      if (!account) {
        throw notFound('Group chat target not found.');
      }
      if (normalizeCompany(account.company_name) !== companyName) {
        throw forbidden('Group chat target must belong to the same company.');
      }
      targets.push(account);
    }
    const title = limit(request.title, 120) || targets.map((item) => item.display_name).slice(0, 8).join(', ') || 'Group chat';
    const room = await tx(async (client) => {
      const roomResult = await client.query(
        `
          INSERT INTO chat_rooms (
            id, code, title, company_name, type, pinned_default, last_message,
            avatar_image_url, last_message_at, created_by_account_id, created_at
          )
          VALUES ($1, $2, $3, $4, 'GROUP', false, '', $5, now(), $6, now())
          RETURNING *
        `,
        [randomUUID(), `group-${randomUUID()}`, title, companyName, request.avatarImageUrl || null, principal.userId]
      );
      await this.ensureMember(client, roomResult.rows[0].id, principal.userId);
      for (const target of targets) {
        await this.ensureMember(client, roomResult.rows[0].id, target.id);
      }
      return roomResult.rows[0];
    });
    const response = await this.roomResponse(room, principal);
    await this.publishRoomState(response);
    return response;
  }

  async startSelfRoom(principal, req = null) {
    const companyName = await effectiveCompany(principal, req);
    const roomCode = `self-${principal.userId}`;
    const room = await tx(async (client) => {
      const existing = await client.query('SELECT * FROM chat_rooms WHERE code = $1', [roomCode]);
      if (existing.rows[0]) {
        await client.query('UPDATE chat_rooms SET company_name = $2 WHERE code = $1', [roomCode, companyName]);
        await this.ensureMember(client, existing.rows[0].id, principal.userId);
        return existing.rows[0];
      }
      const result = await client.query(
        `
          INSERT INTO chat_rooms (
            id, code, title, company_name, type, pinned_default, last_message,
            last_message_at, created_by_account_id, created_at
          )
          VALUES ($1, $2, $3, $4, 'SELF', false, '', now(), $5, now())
          RETURNING *
        `,
        [randomUUID(), roomCode, '\ub098\uc640\uc758 \ucc44\ud305', companyName, principal.userId]
      );
      await this.ensureMember(client, result.rows[0].id, principal.userId);
      return result.rows[0];
    });
    const response = await this.roomResponse(room, principal);
    await this.publishRoomState(response);
    return response;
  }

  async ensureMember(client, roomId, accountId) {
    await client.query(
      `
        INSERT INTO chat_room_members (id, room_id, account_id, joined_at)
        VALUES ($1, $2, $3, now())
        ON CONFLICT (room_id, account_id) DO NOTHING
      `,
      [randomUUID(), roomId, accountId]
    );
  }

  async recentMessages(roomCode, principal, limitValue = 80) {
    const membership = await this.assertMember(roomCode, principal);
    const limitCount = Math.max(1, Math.min(Number(limitValue) || 80, 200));
    const result = await query(
      `
        SELECT msg.*, p.nickname AS sender_nickname, p.avatar_color AS sender_avatar_color,
               p.avatar_image_url AS sender_avatar_image_url
        FROM chat_message_records msg
        LEFT JOIN user_profiles p ON p.account_id = msg.sender_id
        WHERE msg.room_code = $1
          AND ($3::timestamptz IS NULL OR msg.sent_at >= $3::timestamptz)
        ORDER BY msg.sent_at DESC
        LIMIT $2
      `,
      [roomCode, limitCount, membership && membership.joined_at ? membership.joined_at : null]
    );
    const rows = result.rows.reverse();
    return this.messagesWithUnread(rows, roomCode);
  }

  async messagesBefore(roomCode, messageId, principal, limitValue = 80) {
    await this.assertMember(roomCode, principal);
    const limitCount = Math.max(1, Math.min(Number(limitValue) || 80, 200));
    const boundary = await query('SELECT sent_at FROM chat_message_records WHERE id = $1 AND room_code = $2', [messageId, roomCode]);
    if (!boundary.rows[0]) {
      throw notFound('Chat message not found.');
    }
    const result = await query(
      `
        SELECT msg.*, p.nickname AS sender_nickname, p.avatar_color AS sender_avatar_color,
               p.avatar_image_url AS sender_avatar_image_url
        FROM chat_message_records msg
        LEFT JOIN user_profiles p ON p.account_id = msg.sender_id
        WHERE msg.room_code = $1 AND msg.sent_at < $2
        ORDER BY msg.sent_at DESC
        LIMIT $3
      `,
      [roomCode, boundary.rows[0].sent_at, limitCount]
    );
    const rows = result.rows.reverse();
    return this.messagesWithUnread(rows, roomCode);
  }

  async messagesAround(roomCode, messageId, principal, before = 40, after = 40) {
    await this.assertMember(roomCode, principal);
    const target = await query('SELECT sent_at FROM chat_message_records WHERE id = $1 AND room_code = $2', [messageId, roomCode]);
    if (!target.rows[0]) {
      throw notFound('Chat message not found.');
    }
    const beforeCount = Math.max(0, Math.min(Number(before) || 40, 80));
    const afterCount = Math.max(0, Math.min(Number(after) || 40, 80));
    const result = await query(
      `
        WITH previous AS (
          SELECT * FROM chat_message_records
          WHERE room_code = $1 AND sent_at < $2
          ORDER BY sent_at DESC
          LIMIT $3
        ),
        current AS (
          SELECT * FROM chat_message_records WHERE id = $5 AND room_code = $1
        ),
        next_rows AS (
          SELECT * FROM chat_message_records
          WHERE room_code = $1 AND sent_at > $2
          ORDER BY sent_at ASC
          LIMIT $4
        )
        SELECT msg.*, p.nickname AS sender_nickname, p.avatar_color AS sender_avatar_color,
               p.avatar_image_url AS sender_avatar_image_url
        FROM (
          SELECT * FROM previous
          UNION ALL SELECT * FROM current
          UNION ALL SELECT * FROM next_rows
        ) msg
        LEFT JOIN user_profiles p ON p.account_id = msg.sender_id
        ORDER BY msg.sent_at ASC
      `,
      [roomCode, target.rows[0].sent_at, beforeCount, afterCount, messageId]
    );
    return this.messagesWithUnread(result.rows, roomCode);
  }

  async messageUnreadCount(messageId, roomCode) {
    const result = await query(
      `
        SELECT GREATEST(COUNT(m.account_id) - COUNT(rr.account_id), 0)::int AS count
        FROM chat_room_members m
        JOIN chat_rooms r ON r.id = m.room_id
        JOIN chat_message_records msg ON msg.id = $1 AND msg.room_code = r.code
        LEFT JOIN chat_message_read_receipts rr ON rr.message_id = msg.id AND rr.account_id = m.account_id
        WHERE r.code = $2
          AND m.joined_at <= msg.sent_at
      `,
      [messageId, roomCode]
    );
    return result.rows[0] ? Number(result.rows[0].count) : 0;
  }

  async messageUnreadCounts(messageIds, roomCode) {
    const uniqueIds = Array.from(new Set((messageIds || []).filter(Boolean).map(String)));
    const counts = new Map(uniqueIds.map((id) => [id, 0]));
    if (uniqueIds.length === 0) {
      return counts;
    }
    const result = await query(
      `
        SELECT msg.id::text AS id, GREATEST(COUNT(m.account_id) - COUNT(rr.account_id), 0)::int AS count
        FROM chat_message_records msg
        JOIN chat_rooms r ON r.code = msg.room_code
        JOIN chat_room_members m ON m.room_id = r.id AND m.joined_at <= msg.sent_at
        LEFT JOIN chat_message_read_receipts rr ON rr.message_id = msg.id AND rr.account_id = m.account_id
        WHERE msg.room_code = $1
          AND msg.id = ANY($2::uuid[])
        GROUP BY msg.id
      `,
      [roomCode, uniqueIds]
    );
    for (const row of result.rows) {
      counts.set(row.id, Number(row.count || 0));
    }
    return counts;
  }

  async messagesWithUnread(rows, roomCode) {
    const counts = await this.messageUnreadCounts(rows.map((row) => row.id), roomCode);
    return rows.map((row) => messageResponse(row, counts.get(String(row.id)) || 0));
  }

  async resolveMentions(roomCode, requestMentions, content) {
    const memberRows = await query(
      `
        SELECT a.id, a.display_name
        FROM chat_room_members m
        JOIN chat_rooms r ON r.id = m.room_id
        JOIN user_accounts a ON a.id = m.account_id
        WHERE r.code = $1
      `,
      [roomCode]
    );
    const memberNames = new Map(memberRows.rows.map((row) => [row.id, row.display_name]));
    const mentions = new Map();
    for (const mention of requestMentions || []) {
      if (mention && mention.userId && memberNames.has(String(mention.userId))) {
        mentions.set(String(mention.userId), limit(mention.displayName || memberNames.get(String(mention.userId)), 120));
      }
    }
    const tokens = String(content || '').matchAll(/(?<!\S)@([^\s@]{1,80})/g);
    for (const match of tokens) {
      for (const [id, name] of memberNames.entries()) {
        if (name === match[1]) {
          mentions.set(id, name);
        }
      }
    }
    return Array.from(mentions.entries()).map(([userId, displayName]) => ({ userId, displayName }));
  }

  async sendMessage(roomCode, request, principal) {
    if (roomCode.startsWith('azoom-') || roomCode.startsWith('azoom:') || roomCode.startsWith('azoom_')) {
      throw badRequest('AZOOM text chat rooms are no longer supported.');
    }
    const content = limit(request.content, 2000);
    if (!content) {
      throw badRequest('Message content is required.');
    }
    await this.assertMember(roomCode, principal);
    const sender = await accountWithProfile(principal.userId);
    if (!sender) {
      throw notFound('Account not found.');
    }
    const mentions = await this.resolveMentions(roomCode, request.mentions || [], content);
    const mentionIds = mentions.map((item) => item.userId).join(',') || null;
    const mentionNames = mentions.map((item) => item.displayName).join('\n') || null;
    const attachment = request.attachment || null;
    const saved = await tx(async (client) => {
      const inserted = await client.query(
        `
          INSERT INTO chat_message_records (
            id, room_code, sender_id, sender_name, content, sent_at,
            system_message, silent_message, spoiler_message, deleted_for_everyone,
            attachment_id, attachment_group_id, attachment_file_name,
            attachment_content_type, attachment_size, attachment_stored_path,
            mention_user_ids, mention_display_names
          )
          VALUES ($1, $2, $3, $4, $5, now(), false, $6, $7, false, $8, $9, $10, $11, $12, $13, $14, $15)
          RETURNING *
        `,
        [
          randomUUID(),
          roomCode,
          principal.userId,
          sender.display_name,
          content,
          Boolean(request.silent),
          Boolean(request.spoiler),
          attachment ? attachment.id : null,
          attachment ? attachment.groupId || null : null,
          attachment ? attachment.fileName || null : null,
          attachment ? attachment.contentType || null : null,
          attachment ? attachment.size || 0 : null,
          attachment ? attachment.storedPath || null : null,
          mentionIds,
          mentionNames
        ]
      );
      const message = inserted.rows[0];
      await client.query(
        `
          INSERT INTO chat_message_read_receipts (id, message_id, room_code, account_id, read_at)
          VALUES ($1, $2, $3, $4, now())
          ON CONFLICT (message_id, account_id) DO NOTHING
        `,
        [randomUUID(), message.id, roomCode, principal.userId]
      );
      await client.query(
        `
          UPDATE chat_rooms
          SET last_message = $2,
              last_message_spoiler = $3,
              last_message_at = now()
          WHERE code = $1
        `,
        [roomCode, content, Boolean(request.spoiler)]
      );
      for (const mention of mentions) {
        if (mention.userId === principal.userId) {
          continue;
        }
        await client.query(
          `
            INSERT INTO chat_mention_notifications (
              id, message_id, mentioned_account_id, room_code, mention_display_name, created_at
            )
            VALUES ($1, $2, $3, $4, $5, now())
            ON CONFLICT (message_id, mentioned_account_id) DO NOTHING
          `,
          [randomUUID(), message.id, mention.userId, roomCode, mention.displayName]
        );
      }
      return message;
    });
    const senderProfile = toProfileResponse(sender);
    const response = messageResponse(saved, await this.messageUnreadCount(saved.id, roomCode), senderProfile);
    await this.publishMessage(roomCode, response, true);
    return response;
  }

  async attachmentForDownload(roomCode, attachmentId, principal) {
    await this.assertMember(roomCode, principal);
    const result = await query(
      `
        SELECT attachment_file_name, attachment_content_type, attachment_size, attachment_stored_path
        FROM chat_message_records
        WHERE room_code = $1
          AND attachment_id = $2
          AND deleted_for_everyone = false
        LIMIT 1
      `,
      [roomCode, attachmentId]
    );
    const row = result.rows[0];
    if (!row || !row.attachment_stored_path) {
      throw notFound('Chat attachment not found.');
    }
    return {
      filePath: row.attachment_stored_path,
      fileName: repairLatin1Utf8FileName(row.attachment_file_name || 'attachment'),
      contentType: row.attachment_content_type || 'application/octet-stream',
      size: Number(row.attachment_size || 0)
    };
  }

  async publishMessage(roomCode, message, notifyMobile) {
    this.realtimeHub.publish(`/topic/rooms/${roomCode}`, message);
    const [room, members] = await Promise.all([
      this.findRoom(roomCode),
      this.members(roomCode)
    ]);
    if (!room) {
      return;
    }
    const roomsByMember = await this.roomResponsesForMembers(room, members);
    for (const member of members) {
      const recipientRoom = roomsByMember.get(member.id);
      if (!recipientRoom) {
        continue;
      }
      const event = { type: 'message', room: recipientRoom, message };
      this.realtimeHub.sendToUser(member.email, '/queue/chat-events', event);
      if (notifyMobile && member.id !== message.senderId && !message.silent) {
        this.createMobilePush(member, recipientRoom, message).catch((error) => {
          console.error('[AVA] Failed to create mobile push event.', error);
        });
      }
    }
  }

  async publishRoomState(roomResponseValue) {
    const room = await this.findRoom(roomResponseValue.code);
    if (!room) {
      return;
    }
    const members = roomResponseValue.members && roomResponseValue.members.length > 0
      ? roomResponseValue.members
      : await this.members(roomResponseValue.code);
    const roomsByMember = await this.roomResponsesForMembers(room, members);
    for (const member of members) {
      const recipientRoom = roomsByMember.get(member.id);
      if (!recipientRoom) {
        continue;
      }
      this.realtimeHub.sendToUser(member.email, '/queue/chat-events', {
        type: 'room',
        room: recipientRoom,
        message: null
      });
    }
  }

  async createMobilePush(member, room, message) {
    const title = room.title || message.senderName;
    const body = message.spoiler ? '\uc2a4\ud3ec\uc77c\ub7ec \uba54\uc2dc\uc9c0' : message.content;
    const data = {
      roomId: room.code,
      messageId: message.id,
      senderId: message.senderId
    };
    const result = await query(
      `
        INSERT INTO mobile_push_events (
          id, account_id, type, title, body, room_id, room_title, sender_name,
          sender_nickname, avatar_color, source_type, source_id, data_json, created_at
        )
        VALUES ($1, $2, 'chat_message', $3, $4, $5, $6, $7, $8, $9, 'chat', $10, $11, now())
        RETURNING *
      `,
      [
        randomUUID(),
        member.id,
        title,
        body,
        room.code,
        room.title,
        message.senderName,
        message.senderNickname || '',
        message.senderAvatarColor || '#7AA06A',
        message.id,
        JSON.stringify(data)
      ]
    );
    const event = this.mobilePushResponse(result.rows[0]);
    this.realtimeHub.sendToUser(member.email, '/queue/mobile-push', event);
  }

  mobilePushResponse(row) {
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

  async publishTyping(roomCode, request, principal) {
    await this.assertMember(roomCode, principal);
    this.realtimeHub.publish(`/topic/rooms/${roomCode}/typing`, {
      roomCode,
      userId: principal.userId,
      displayName: principal.displayName,
      typing: Boolean(request.typing),
      at: new Date().toISOString()
    });
  }

  async markRead(roomCode, principal) {
    const membership = await this.assertMember(roomCode, principal);
    const unread = await query(
      `
        SELECT msg.id, msg.room_code
        FROM chat_message_records msg
        WHERE msg.room_code = $1
          AND ($3::timestamptz IS NULL OR msg.sent_at >= $3::timestamptz)
          AND NOT EXISTS (
            SELECT 1 FROM chat_message_read_receipts rr
            WHERE rr.message_id = msg.id AND rr.account_id = $2
          )
      `,
      [roomCode, principal.userId, membership && membership.joined_at ? membership.joined_at : null]
    );
    for (let start = 0; start < unread.rows.length; start += 500) {
      const chunk = unread.rows.slice(start, start + 500);
      const values = [];
      const placeholders = chunk.map((row, index) => {
        const offset = index * 4;
        values.push(randomUUID(), row.id, row.room_code, principal.userId);
        return `($${offset + 1}, $${offset + 2}, $${offset + 3}, $${offset + 4}, now())`;
      });
      await query(
        `
          INSERT INTO chat_message_read_receipts (id, message_id, room_code, account_id, read_at)
          VALUES ${placeholders.join(', ')}
          ON CONFLICT (message_id, account_id) DO NOTHING
        `,
        values
      );
    }
    const result = await query(
      `
        SELECT id
        FROM chat_message_records
        WHERE room_code = $1
        ORDER BY sent_at DESC
        LIMIT 200
      `,
      [roomCode]
    );
    const rows = result.rows.reverse();
    const counts = await this.messageUnreadCounts(rows.map((row) => row.id), roomCode);
    const messages = rows.map((row) => ({
      messageId: String(row.id),
      unreadCount: counts.get(String(row.id)) || 0
    }));
    const response = { roomCode, messages };
    this.realtimeHub.publish(`/topic/rooms/${roomCode}/read-state`, response);
    await this.publishRoomState(await this.roomForMember(roomCode, principal.userId));
    return response;
  }

  async deleteForEveryone(roomCode, messageId, principal) {
    await this.assertMember(roomCode, principal);
    const result = await query(
      `
        UPDATE chat_message_records
        SET content = $3,
            deleted_for_everyone = true,
            silent_message = false,
            spoiler_message = false,
            attachment_id = NULL,
            attachment_group_id = NULL,
            attachment_file_name = NULL,
            attachment_content_type = NULL,
            attachment_size = NULL,
            attachment_stored_path = NULL,
            mention_user_ids = NULL,
            mention_display_names = NULL
        WHERE id = $1 AND room_code = $2 AND sender_id = $4
        RETURNING *
      `,
      [messageId, roomCode, '\uc0ad\uc81c\ub41c \uba54\uc2dc\uc9c0\uc785\ub2c8\ub2e4', principal.userId]
    );
    if (!result.rows[0]) {
      throw notFound('Chat message not found.');
    }
    const response = messageResponse(result.rows[0], await this.messageUnreadCount(messageId, roomCode));
    await this.publishMessage(roomCode, response, false);
    return response;
  }

  async setPinned(roomCode, request, principal) {
    const pinned = Boolean(request && request.pinned);
    const row = await query(
      'SELECT pinned_room_ids_json FROM user_chat_folder_settings WHERE account_id = $1',
      [principal.userId]
    );
    const ids = parseJsonList(row.rows[0] && row.rows[0].pinned_room_ids_json).filter((id) => id !== roomCode);
    if (pinned) {
      ids.unshift(roomCode);
    }
    await query(
      `
        INSERT INTO user_chat_folder_settings (
          account_id, folders_json, filter_order_json, quiet_room_ids_json, pinned_room_ids_json, updated_at
        )
        VALUES ($1, '[]', '[]', '[]', $2, now())
        ON CONFLICT (account_id)
        DO UPDATE SET pinned_room_ids_json = EXCLUDED.pinned_room_ids_json, updated_at = now()
      `,
      [principal.userId, JSON.stringify(ids)]
    );
    const room = await this.findRoom(roomCode);
    return this.roomResponse(room, principal);
  }

  async setNotice(roomCode, request, principal) {
    const content = limit(request.content || request.notice || request.message, 2000);
    await this.assertMember(roomCode, principal);
    const result = await query(
      `
        UPDATE chat_rooms
        SET notice_message_id = $2,
            notice_sender_id = $3,
            notice_sender_name = $4,
            notice_content = $5,
            notice_sent_at = now()
        WHERE code = $1
        RETURNING *
      `,
      [roomCode, request.messageId || '', principal.userId, principal.displayName, content]
    );
    if (!result.rows[0]) {
      throw notFound('Chat room not found.');
    }
    const response = await this.roomResponse(result.rows[0], principal);
    await this.publishRoomState(response);
    return response;
  }

  async mentionNotifications(status, principal, limitValue = 80) {
    const limitCount = Math.max(1, Math.min(Number(limitValue) || 80, 200));
    const statusSql = status === 'checked' ? 'AND n.checked_at IS NOT NULL' : status === 'requested' ? 'AND n.checked_at IS NULL' : '';
    const result = await query(
      `
        SELECT n.*, msg.content, msg.sender_id, msg.sender_name, msg.sent_at,
               r.title AS room_title
        FROM chat_mention_notifications n
        JOIN chat_message_records msg ON msg.id = n.message_id
        JOIN chat_rooms r ON r.code = n.room_code
        WHERE n.mentioned_account_id = $1
        ${statusSql}
        ORDER BY n.created_at DESC
        LIMIT $2
      `,
      [principal.userId, limitCount]
    );
    const membersByRoom = await this.membersByRoomCodes(result.rows.map((row) => row.room_code));
    return result.rows.map((row) => {
      const roomMembers = membersByRoom.get(row.room_code) || [];
      return {
        id: row.id,
        roomCode: row.room_code,
        roomTitle: row.room_title,
        participantCount: roomMembers.length,
        members: roomMembers,
        messageId: row.message_id,
        senderId: row.sender_id,
        senderName: row.sender_name,
        senderNickname: '',
        senderAvatarColor: '#7AA06A',
        senderAvatarImageUrl: '',
        mentionDisplayName: row.mention_display_name,
        content: row.content,
        sentAt: row.sent_at,
        checkedAt: row.checked_at,
        checked: Boolean(row.checked_at)
      };
    });
  }

  async markMentionNotificationChecked(notificationId, principal) {
    const result = await query(
      `
        UPDATE chat_mention_notifications
        SET checked_at = COALESCE(checked_at, now())
        WHERE id = $1 AND mentioned_account_id = $2
        RETURNING *
      `,
      [notificationId, principal.userId]
    );
    if (!result.rows[0]) {
      throw notFound('Mention notification not found.');
    }
    const list = await this.mentionNotifications('all', principal, 200);
    return list.find((item) => item.id === result.rows[0].id) || null;
  }

  async leaveRoom(roomCode, principal) {
    const room = await this.findRoom(roomCode);
    if (!room) {
      throw notFound('Chat room not found.');
    }
    await query(
      `
        DELETE FROM chat_room_members
        WHERE account_id = $1 AND room_id = (SELECT id FROM chat_rooms WHERE code = $2)
      `,
      [principal.userId, roomCode]
    );
    const responseRoom = await this.roomResponse(room, principal).catch(() => ({
      code: room.code,
      title: room.title,
      type: room.type,
      members: []
    }));
    return {
      room: responseRoom,
      message: messageResponse({
        id: randomUUID(),
        room_code: roomCode,
        sender_id: principal.userId,
        sender_name: principal.displayName,
        content: `${principal.displayName} left the chat.`,
        sent_at: new Date().toISOString(),
        system_message: true,
        silent_message: true,
        spoiler_message: false,
        deleted_for_everyone: false
      }),
      deleted: false,
      leaverEmail: principal.email
    };
  }
}

module.exports = {
  ChatService
};
