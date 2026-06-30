const { one, query } = require('../db');

const ONLINE = '\uc628\ub77c\uc778';
const BACKGROUND = '\ubc31\uadf8\ub77c\uc6b4\ub4dc';
const OFFLINE = '\uc624\ud504\ub77c\uc778';
const ACTIVE_STALE_MS = 45 * 1000;
const BACKGROUND_STALE_MS = 10 * 60 * 1000;
const BACKGROUND_COLORS = [
  '#7AA06A',
  '#8BA6C9',
  '#9C8E82',
  '#6D91A8',
  '#A88976',
  '#7986A8',
  '#7A9A90',
  '#A0A76F'
];

function blankToNull(value) {
  return value == null || String(value).trim() === '' ? null : value;
}

function blankToDefault(value, fallback) {
  return value == null || String(value).trim() === '' ? fallback : value;
}

function normalizeCompany(value) {
  if (!value || String(value).trim() === '') {
    return 'ABBA-S';
  }
  const normalized = String(value).trim().replace(/\s+/g, ' ');
  if (normalized.toLowerCase() === 'cadillac' || normalized.toLowerCase() === 'cadillak') {
    return 'Cadillac';
  }
  return 'ABBA-S';
}

function normalizeStatus(value) {
  if (!value) {
    return OFFLINE;
  }
  const trimmed = String(value).trim();
  if (trimmed === ONLINE || trimmed === BACKGROUND || trimmed === OFFLINE) {
    return trimmed;
  }
  switch (trimmed.toLowerCase()) {
    case 'online':
      return ONLINE;
    case 'background':
    case 'away':
    case 'idle':
      return BACKGROUND;
    default:
      return OFFLINE;
  }
}

function effectiveStatus(profile) {
  const status = normalizeStatus(profile.status);
  if (status === OFFLINE) {
    return OFFLINE;
  }
  const updatedAt = profile.presence_updated_at ? new Date(profile.presence_updated_at).getTime() : 0;
  if (!updatedAt) {
    return OFFLINE;
  }
  const staleMs = status === BACKGROUND ? BACKGROUND_STALE_MS : ACTIVE_STALE_MS;
  return updatedAt + staleMs < Date.now() ? OFFLINE : status;
}

function hashCode(value) {
  let hash = 0;
  const text = String(value || '');
  for (let index = 0; index < text.length; index += 1) {
    hash = ((hash << 5) - hash + text.charCodeAt(index)) | 0;
  }
  return hash;
}

function profileBackgroundColor(accountId, color) {
  if (color && /^#[0-9a-fA-F]{6}$/.test(color)) {
    return color;
  }
  const index = Math.abs(hashCode(accountId)) % BACKGROUND_COLORS.length;
  return BACKGROUND_COLORS[index];
}

function toProfileResponse(row, blocked = false) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    email: row.email,
    name: row.display_name,
    displayName: row.display_name,
    nickname: blankToDefault(row.nickname, row.display_name),
    phoneNumber: blankToNull(row.phone_number),
    contactEmail: blankToNull(row.contact_email),
    gender: blankToNull(row.gender),
    role: row.role,
    companyName: normalizeCompany(row.company_name),
    position: blankToDefault(row.position, 'Staff'),
    department: blankToDefault(row.department, 'Unknown'),
    birthDate: row.birth_date || null,
    status: effectiveStatus(row),
    avatarColor: blankToDefault(row.avatar_color, '#7AA06A'),
    statusMessage: blankToNull(row.status_message),
    avatarImageUrl: blankToNull(row.avatar_image_url),
    profileBackgroundColor: profileBackgroundColor(row.id, row.profile_background_color),
    profileBackgroundImageUrl: blankToNull(row.profile_background_image_url),
    blocked
  };
}

async function accountWithProfile(accountId, client = null) {
  const executor = client || { query };
  const result = await executor.query(
    `
      SELECT
        a.id, a.email, a.password_hash, a.display_name, a.role, a.enabled,
        p.department, p.company_name, p.position, p.nickname, p.phone_number,
        p.contact_email, p.gender, p.birth_date, p.status, p.presence_updated_at,
        p.avatar_color, p.status_message, p.avatar_image_url,
        p.profile_background_color, p.profile_background_image_url
      FROM user_accounts a
      LEFT JOIN user_profiles p ON p.account_id = a.id
      WHERE a.id = $1
    `,
    [accountId]
  );
  return result.rows[0] || null;
}

async function accountByEmail(email, client = null) {
  const executor = client || { query };
  const result = await executor.query(
    `
      SELECT
        a.id, a.email, a.password_hash, a.display_name, a.role, a.enabled,
        p.department, p.company_name, p.position, p.nickname, p.phone_number,
        p.contact_email, p.gender, p.birth_date, p.status, p.presence_updated_at,
        p.avatar_color, p.status_message, p.avatar_image_url,
        p.profile_background_color, p.profile_background_image_url
      FROM user_accounts a
      LEFT JOIN user_profiles p ON p.account_id = a.id
      WHERE lower(a.email) = lower($1)
    `,
    [email]
  );
  return result.rows[0] || null;
}

async function profilesForPrincipal(principal) {
  const companyName = await effectiveCompany(principal);
  const result = await query(
    `
      SELECT
        a.id, a.email, a.display_name, a.role,
        p.department, p.company_name, p.position, p.nickname, p.phone_number,
        p.contact_email, p.gender, p.birth_date, p.status, p.presence_updated_at,
        p.avatar_color, p.status_message, p.avatar_image_url,
        p.profile_background_color, p.profile_background_image_url
      FROM user_accounts a
      LEFT JOIN user_profiles p ON p.account_id = a.id
      WHERE a.enabled = true
        AND COALESCE(p.company_name, 'ABBA-S') = $1
      ORDER BY a.display_name ASC
    `,
    [companyName]
  );
  return result.rows.map((row) => toProfileResponse(row));
}

async function effectiveCompany(principal, req = null) {
  const row = await one('SELECT company_name FROM user_profiles WHERE account_id = $1', [principal.userId]);
  const ownCompany = normalizeCompany(row && row.company_name);
  if (principal.role !== 'SUPERUSER') {
    return ownCompany;
  }
  const requested = req && req.get && req.get('X-AVA-Company');
  return requested ? normalizeCompany(requested) : ownCompany;
}

module.exports = {
  ONLINE,
  BACKGROUND,
  OFFLINE,
  normalizeCompany,
  toProfileResponse,
  accountWithProfile,
  accountByEmail,
  profilesForPrincipal,
  effectiveCompany
};
