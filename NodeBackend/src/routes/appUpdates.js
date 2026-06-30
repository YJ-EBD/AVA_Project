const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { randomUUID } = require('crypto');
const config = require('../config');
const { query } = require('../db');
const { asyncHandler, badRequest, notFound } = require('../errors');

const router = express.Router();

function normalizeVersion(version) {
  if (!version || String(version).trim() === '') {
    return '0.0.0';
  }
  return String(version).trim().split('+')[0].toLowerCase();
}

function versionParts(version) {
  return normalizeVersion(version).split('.').map((part) => {
    const value = Number.parseInt(part.replace(/[^0-9].*$/, ''), 10);
    return Number.isFinite(value) ? value : 0;
  });
}

function compareVersions(left, right) {
  const leftParts = versionParts(left);
  const rightParts = versionParts(right);
  const count = Math.max(leftParts.length, rightParts.length);
  for (let index = 0; index < count; index += 1) {
    const leftValue = leftParts[index] || 0;
    const rightValue = rightParts[index] || 0;
    if (leftValue !== rightValue) {
      return leftValue > rightValue ? 1 : -1;
    }
  }
  return 0;
}

function platformConfig(platform) {
  const normalized = String(platform || '').trim().toLowerCase();
  const platformValue = config.updates[normalized];
  if (!platformValue) {
    throw badRequest('Unsupported update platform.');
  }
  return platformValue;
}

function packagePath(fileName) {
  return path.resolve(config.updateDirectory, fileName);
}

function sha256(filePath) {
  if (!fs.existsSync(filePath)) {
    return '';
  }
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(filePath));
  return hash.digest('hex');
}

async function upsertRelease(update, available, checksum, sizeBytes) {
  const result = await query(
    `
      INSERT INTO app_update_releases (
        id, platform, version, file_name, required, release_notes, sha256,
        size_bytes, package_available, created_at, updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now(), now())
      ON CONFLICT (platform, version)
      DO UPDATE SET
        file_name = EXCLUDED.file_name,
        required = EXCLUDED.required,
        release_notes = EXCLUDED.release_notes,
        sha256 = EXCLUDED.sha256,
        size_bytes = EXCLUDED.size_bytes,
        package_available = EXCLUDED.package_available,
        updated_at = now()
      RETURNING *
    `,
    [
      randomUUID(),
      update.platform,
      normalizeVersion(update.latestVersion),
      update.fileName,
      Boolean(update.required),
      update.releaseNotes || '',
      checksum,
      sizeBytes,
      available
    ]
  );
  return result.rows[0];
}

router.get('/:platform/latest', asyncHandler(async (req, res) => {
  const update = platformConfig(req.params.platform);
  const currentVersion = normalizeVersion(req.query.currentVersion);
  const filePath = packagePath(update.fileName);
  const available = fs.existsSync(filePath) && fs.statSync(filePath).isFile();
  const sizeBytes = available ? fs.statSync(filePath).size : 0;
  const checksum = available ? sha256(filePath) : '';
  const release = await upsertRelease(update, available, checksum, sizeBytes);
  const updateAvailable = available && compareVersions(release.version, currentVersion) > 0;
  res.json({
    platform: release.platform,
    currentVersion,
    latestVersion: release.version,
    updateAvailable,
    required: updateAvailable && Boolean(release.required),
    fileName: release.file_name,
    downloadUrl: updateAvailable
      ? `/api/app-updates/${release.platform}/download/${encodeURIComponent(release.file_name)}`
      : '',
    sha256: release.sha256 || '',
    sizeBytes: Number(release.size_bytes || 0),
    releaseNotes: release.release_notes || ''
  });
}));

router.get('/:platform/releases/:version', asyncHandler(async (req, res) => {
  const update = platformConfig(req.params.platform);
  if (normalizeVersion(update.latestVersion) === normalizeVersion(req.params.version)) {
    const filePath = packagePath(update.fileName);
    const available = fs.existsSync(filePath) && fs.statSync(filePath).isFile();
    await upsertRelease(update, available, available ? sha256(filePath) : '', available ? fs.statSync(filePath).size : 0);
  }
  const result = await query(
    'SELECT * FROM app_update_releases WHERE platform = $1 AND version = $2',
    [String(req.params.platform).toLowerCase(), normalizeVersion(req.params.version)]
  );
  if (!result.rows[0]) {
    throw notFound('Update release not found.');
  }
  const release = result.rows[0];
  res.json({
    platform: release.platform,
    version: release.version,
    fileName: release.file_name,
    required: Boolean(release.required),
    releaseNotes: release.release_notes,
    sha256: release.sha256 || '',
    sizeBytes: Number(release.size_bytes || 0),
    packageAvailable: Boolean(release.package_available),
    updatedAt: release.updated_at
  });
}));

router.get('/:platform/download/:fileName', asyncHandler(async (req, res) => {
  const update = platformConfig(req.params.platform);
  if (decodeURIComponent(req.params.fileName) !== update.fileName) {
    throw notFound('Unknown update package.');
  }
  const filePath = packagePath(update.fileName);
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    throw notFound('Update package not found.');
  }
  res.download(filePath, update.fileName);
}));

module.exports = router;
