const nodemailer = require('nodemailer');
const config = require('../config');
const { HttpError } = require('../errors');

let transporter = null;
let transporterKey = '';

function smtpConfig() {
  return config.mail && config.mail.smtp ? config.mail.smtp : {};
}

function mailConfigured() {
  const smtp = smtpConfig();
  if (!smtp.host || !smtp.from) {
    return false;
  }
  if (smtp.auth && (!smtp.user || !smtp.password)) {
    return false;
  }
  return true;
}

function transporterForConfig() {
  const smtp = smtpConfig();
  const key = JSON.stringify({
    host: smtp.host,
    port: smtp.port,
    secure: smtp.secure,
    starttls: smtp.starttls,
    auth: smtp.auth,
    user: smtp.user,
    from: smtp.from
  });
  if (transporter && transporterKey === key) {
    return transporter;
  }
  if (!mailConfigured()) {
    throw new HttpError(
      503,
      'MAIL_NOT_CONFIGURED',
      'Email verification is temporarily unavailable.'
    );
  }
  transporterKey = key;
  transporter = nodemailer.createTransport({
    host: smtp.host,
    port: smtp.port,
    secure: Boolean(smtp.secure),
    requireTLS: Boolean(smtp.starttls),
    connectionTimeout: smtp.connectionTimeoutMs,
    greetingTimeout: smtp.timeoutMs,
    socketTimeout: smtp.timeoutMs,
    auth: smtp.auth
      ? {
          user: smtp.user,
          pass: smtp.password
        }
      : undefined
  });
  return transporter;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

async function sendEmailVerificationCode({ email, code, expiresInMinutes }) {
  const smtp = smtpConfig();
  const productName = config.mail.productName || 'AVA';
  const brandName = config.mail.brandName || 'ABBA-S';
  const safeCode = escapeHtml(code);
  const safeProductName = escapeHtml(productName);
  const safeBrandName = escapeHtml(brandName);
  const safeExpires = Number(expiresInMinutes || 5);
  const subject = `[${productName}] Email verification code`;
  const text = [
    `${productName} email verification code`,
    '',
    `Code: ${code}`,
    `This code expires in ${safeExpires} minutes.`,
    '',
    `If you did not request this code, you can ignore this email.`,
    `${brandName}`
  ].join('\n');
  const html = `
    <div style="font-family:Arial,Helvetica,sans-serif;line-height:1.5;color:#111827">
      <h2 style="margin:0 0 12px">${safeProductName} email verification</h2>
      <p style="margin:0 0 16px">Enter this code on the signup page.</p>
      <div style="font-size:28px;font-weight:700;letter-spacing:6px;padding:14px 18px;border-radius:10px;background:#f3f6fb;display:inline-block">${safeCode}</div>
      <p style="margin:16px 0 0;color:#4b5563">This code expires in ${safeExpires} minutes.</p>
      <p style="margin:16px 0 0;color:#6b7280;font-size:13px">If you did not request this code, you can ignore this email.</p>
      <p style="margin:20px 0 0;color:#6b7280;font-size:13px">${safeBrandName}</p>
    </div>
  `;

  try {
    return await transporterForConfig().sendMail({
      from: smtp.from,
      to: email,
      subject,
      text,
      html
    });
  } catch (error) {
    console.error('[AVA] Failed to send email verification code.', {
      to: email,
      host: smtp.host,
      port: smtp.port,
      code: error && error.code ? error.code : undefined,
      command: error && error.command ? error.command : undefined,
      responseCode: error && error.responseCode ? error.responseCode : undefined
    });
    throw new HttpError(
      503,
      'MAIL_SEND_FAILED',
      'Email verification code could not be sent. Please try again shortly.'
    );
  }
}

async function sendSignupVerificationEmail({ email, code, expiresInSeconds }) {
  const seconds = Number(expiresInSeconds || 300);
  return sendEmailVerificationCode({
    email,
    code,
    expiresInMinutes: Math.max(1, Math.ceil(seconds / 60))
  });
}

module.exports = {
  mailConfigured,
  sendEmailVerificationCode,
  sendSignupVerificationEmail
};
