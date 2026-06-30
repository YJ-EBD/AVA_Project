const crypto = require('crypto');
const config = require('./config');

function base64Url(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function base64UrlJson(value) {
  return base64Url(JSON.stringify(value));
}

function decodeBase64Url(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=');
  return Buffer.from(padded, 'base64').toString('utf8');
}

function sign(headerPayload) {
  return crypto.createHmac('sha256', config.jwtSecret).update(headerPayload).digest('base64url');
}

function createToken({ account, sessionId, type, expiresInSeconds }) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const headerPayload = [
    base64UrlJson({ alg: 'HS256', typ: 'JWT' }),
    base64UrlJson({
      sub: account.id,
      email: account.email,
      name: account.display_name,
      role: account.role,
      sid: sessionId,
      typ: type,
      iat: nowSeconds,
      exp: nowSeconds + expiresInSeconds
    })
  ].join('.');
  return `${headerPayload}.${sign(headerPayload)}`;
}

function parseToken(token) {
  if (!token || typeof token !== 'string') {
    return null;
  }
  const parts = token.split('.');
  if (parts.length !== 3) {
    return null;
  }
  const headerPayload = `${parts[0]}.${parts[1]}`;
  const expected = sign(headerPayload);
  const actual = parts[2];
  const expectedBytes = Buffer.from(expected);
  const actualBytes = Buffer.from(actual);
  if (expectedBytes.length !== actualBytes.length || !crypto.timingSafeEqual(expectedBytes, actualBytes)) {
    return null;
  }
  try {
    const claims = JSON.parse(decodeBase64Url(parts[1]));
    if (!claims.exp || Number(claims.exp) <= Math.floor(Date.now() / 1000)) {
      return null;
    }
    return {
      userId: claims.sub,
      email: claims.email,
      displayName: claims.name,
      role: claims.role,
      sessionId: claims.sid,
      type: claims.typ
    };
  } catch {
    return null;
  }
}

function issueTokens(account, sessionId) {
  const accessSeconds = config.accessTokenMinutes * 60;
  const refreshSeconds = config.refreshTokenDays * 24 * 60 * 60;
  return {
    accessToken: createToken({ account, sessionId, type: 'access', expiresInSeconds: accessSeconds }),
    refreshToken: createToken({ account, sessionId, type: 'refresh', expiresInSeconds: refreshSeconds }),
    tokenType: 'Bearer',
    expiresInSeconds: accessSeconds
  };
}

module.exports = {
  parseToken,
  issueTokens
};
