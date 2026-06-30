const path = require('path');

const fallbackName = 'attachment';

function stripPathSegments(value) {
  const normalized = String(value || '').replace(/\\/g, '/');
  return path.posix.basename(normalized).trim();
}

function hasLikelyLatin1Utf8Mojibake(value) {
  const text = String(value || '');
  if (!text) {
    return false;
  }
  if (/[\u0080-\u009f]/.test(text)) {
    return true;
  }
  return /[ÃÂÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝàáâãäåæçèéêëìíîï]/.test(text);
}

function scoreReadableFileName(value) {
  const text = String(value || '');
  let score = 0;
  if (/[가-힣]/.test(text)) {
    score += 8;
  }
  if (/[A-Za-z0-9._ -]/.test(text)) {
    score += 1;
  }
  if (/[\u0080-\u009f]/.test(text)) {
    score -= 5;
  }
  if (text.includes('\uFFFD')) {
    score -= 10;
  }
  return score;
}

function repairLatin1Utf8FileName(value) {
  const fileName = stripPathSegments(value);
  if (!fileName) {
    return fallbackName;
  }
  if (!hasLikelyLatin1Utf8Mojibake(fileName)) {
    return fileName;
  }
  const repaired = Buffer.from(fileName, 'latin1').toString('utf8');
  if (!repaired || repaired.includes('\uFFFD')) {
    return fileName;
  }
  return scoreReadableFileName(repaired) > scoreReadableFileName(fileName)
    ? stripPathSegments(repaired) || fileName
    : fileName;
}

function uploadFileName(file, fallback = fallbackName) {
  const repaired = repairLatin1Utf8FileName(file && file.originalname);
  return repaired === fallbackName ? fallback : repaired;
}

module.exports = {
  repairLatin1Utf8FileName,
  uploadFileName
};
