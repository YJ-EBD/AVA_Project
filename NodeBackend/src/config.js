const fs = require('fs');
const path = require('path');
const dotenv = require('dotenv');

const rootDir = path.resolve(__dirname, '..', '..');
const backendDir = path.resolve(__dirname, '..');

for (const envPath of [
  path.join(rootDir, '.env'),
  path.join(rootDir, '.env.local'),
  path.join(backendDir, '.env'),
  path.join(backendDir, '.env.local'),
  path.join(backendDir, 'LiveKit', 'azoom-livekit.env')
]) {
  if (fs.existsSync(envPath)) {
    dotenv.config({ path: envPath, override: false });
  }
}

function env(name, fallback = '') {
  const value = process.env[name];
  return value == null || value === '' ? fallback : value;
}

function boolEnv(name, fallback = false) {
  const value = env(name, String(fallback)).trim().toLowerCase();
  return value === 'true' || value === '1' || value === 'yes' || value === 'y';
}

function intEnv(name, fallback) {
  const value = Number.parseInt(env(name, String(fallback)), 10);
  return Number.isFinite(value) ? value : fallback;
}

function mailEnv(name, fallback = '') {
  return env(`AVA_${name}`, env(`NAVER_${name}`, fallback));
}

function postgresConnection() {
  const rawUrl = env('AVA_POSTGRES_URL', 'jdbc:postgresql://localhost:5432/ava');
  const connectionString = rawUrl.startsWith('jdbc:') ? rawUrl.slice(5) : rawUrl;
  const parsed = new URL(connectionString);
  return {
    host: parsed.hostname || 'localhost',
    port: parsed.port ? Number.parseInt(parsed.port, 10) : 5432,
    database: parsed.pathname ? parsed.pathname.replace(/^\//, '') : 'ava',
    user: env('AVA_POSTGRES_USER', 'ava'),
    password: env('AVA_POSTGRES_PASSWORD', 'ava_password')
  };
}

function updateConfig(platform, versionFallback, fileFallback, notesFallback) {
  const upper = platform.toUpperCase();
  return {
    platform,
    latestVersion: env(`AVA_APP_${upper}_LATEST_VERSION`, versionFallback),
    fileName: env(`AVA_APP_${upper}_FILE_NAME`, fileFallback),
    required: boolEnv(`AVA_APP_${upper}_REQUIRED`, false),
    releaseNotes: env(`AVA_APP_${upper}_RELEASE_NOTES`, notesFallback)
  };
}

module.exports = {
  rootDir,
  backendDir,
  host: env('AVA_BACKEND_HOST', '0.0.0.0'),
  port: intEnv('AVA_BACKEND_PORT', 8080),
  allowedOrigins: env('AVA_ALLOWED_ORIGINS', '*').split(',').map((item) => item.trim()).filter(Boolean),
  jwtSecret: env('AVA_JWT_SECRET', 'ava-local-development-secret-change-me-please-2026'),
  accessTokenMinutes: intEnv('AVA_ACCESS_TOKEN_MINUTES', 30),
  refreshTokenDays: intEnv('AVA_REFRESH_TOKEN_DAYS', 30),
  sessionHours: intEnv('AVA_SESSION_HOURS', 12),
  sessionRememberDays: intEnv('AVA_SESSION_REMEMBER_DAYS', 30),
  mail: {
    brandName: env('MAIL_BRAND_NAME', 'ABBA-S'),
    productName: env('MAIL_PRODUCT_NAME', 'AVA'),
    smtp: {
      host: mailEnv('SMTP_HOST'),
      port: intEnv('AVA_SMTP_PORT', intEnv('NAVER_SMTP_PORT', 465)),
      secure: boolEnv('AVA_SMTP_SSL_ENABLE', boolEnv('NAVER_SMTP_SSL_ENABLE', true)),
      starttls: boolEnv('AVA_SMTP_STARTTLS_ENABLE', boolEnv('NAVER_SMTP_STARTTLS_ENABLE', false)),
      auth: boolEnv('AVA_SMTP_AUTH', boolEnv('NAVER_SMTP_AUTH', true)),
      user: mailEnv('SMTP_USER'),
      password: mailEnv('SMTP_PASS', mailEnv('SMTP_PASSWORD')),
      from: mailEnv('SMTP_FROM'),
      connectionTimeoutMs: intEnv(
        'AVA_SMTP_CONNECTION_TIMEOUT_MS',
        intEnv('NAVER_SMTP_CONNECTION_TIMEOUT_MS', 10000)
      ),
      timeoutMs: intEnv('AVA_SMTP_TIMEOUT_MS', intEnv('NAVER_SMTP_TIMEOUT_MS', 10000)),
      writeTimeoutMs: intEnv('AVA_SMTP_WRITE_TIMEOUT_MS', intEnv('NAVER_SMTP_WRITE_TIMEOUT_MS', 10000))
    }
  },
  postgres: postgresConnection(),
  updateDirectory: path.resolve(backendDir, env('AVA_APP_UPDATE_DIR', 'AppUpdates')),
  livekit: {
    url: env('AVA_LIVEKIT_URL', 'ws://112.166.136.198:8080'),
    apiKey: env('AVA_LIVEKIT_API_KEY', 'ava-azoom'),
    apiSecret: env('AVA_LIVEKIT_API_SECRET', 'ava-local-livekit-secret'),
    tokenMinutes: intEnv('AVA_LIVEKIT_TOKEN_MINUTES', 120)
  },
  updates: {
    windows: updateConfig('windows', '0.1.308', 'ava-windows-0.1.308.zip', 'AVA Windows update'),
    android: updateConfig('android', '0.1.308', 'ava-android-0.1.308.apk', 'AVA Android update'),
    macos: updateConfig('macos', '0.1.306', 'AVA_Project_0.1.306_1306_macOS.dmg', 'AVA macOS update'),
    ios: updateConfig('ios', '0.1.307', 'ava-ios-0.1.307.ipa', 'AVA iOS update')
  }
};
