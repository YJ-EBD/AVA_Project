const net = require('net');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function createSmtpTestServer() {
  const receivedMessages = [];
  const server = net.createServer((socket) => {
    let buffer = '';
    let dataMode = false;
    let dataBuffer = '';

    socket.write('220 ava-test-smtp\r\n');

    socket.on('data', (chunk) => {
      buffer += chunk.toString('utf8');
      while (buffer.includes('\n')) {
        const newline = buffer.indexOf('\n');
        const rawLine = buffer.slice(0, newline + 1);
        buffer = buffer.slice(newline + 1);
        const line = rawLine.replace(/\r?\n$/, '');

        if (dataMode) {
          if (line === '.') {
            receivedMessages.push(dataBuffer);
            dataBuffer = '';
            dataMode = false;
            socket.write('250 accepted\r\n');
          } else {
            dataBuffer += `${line}\n`;
          }
          continue;
        }

        if (line.startsWith('EHLO')) {
          socket.write('250-ava-test-smtp\r\n250 OK\r\n');
        } else if (line.startsWith('MAIL FROM:')) {
          socket.write('250 sender ok\r\n');
        } else if (line.startsWith('RCPT TO:')) {
          socket.write('250 recipient ok\r\n');
        } else if (line === 'DATA') {
          dataMode = true;
          socket.write('354 end with dot\r\n');
        } else if (line === 'QUIT') {
          socket.write('221 bye\r\n');
          socket.end();
        } else {
          socket.write('250 ok\r\n');
        }
      }
    });
  });

  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      resolve({ server, receivedMessages, port: server.address().port });
    });
  });
}

async function main() {
  const { server, receivedMessages, port } = await createSmtpTestServer();
  process.env.AVA_SMTP_HOST = '127.0.0.1';
  process.env.AVA_SMTP_PORT = String(port);
  process.env.AVA_SMTP_SSL_ENABLE = 'false';
  process.env.AVA_SMTP_STARTTLS_ENABLE = 'false';
  process.env.AVA_SMTP_AUTH = 'false';
  process.env.AVA_SMTP_FROM = 'ava-test@example.com';
  process.env.MAIL_BRAND_NAME = 'ABBA-S';
  process.env.MAIL_PRODUCT_NAME = 'AVA';

  try {
    const { sendSignupVerificationEmail } = require('../src/services/mailService');
    await sendSignupVerificationEmail({
      email: 'signup-user@example.com',
      code: '123456',
      expiresInSeconds: 300
    });
    assert(receivedMessages.length === 1, `Expected 1 message, got ${receivedMessages.length}.`);
    const message = receivedMessages[0];
    assert(message.includes('signup-user@example.com'), 'Recipient address was not written.');
    assert(message.includes('123456'), 'Verification code was not written.');
    assert(message.includes('Content-Type: text/html'), 'HTML body was not written.');
    console.log(JSON.stringify({ ok: true, messages: receivedMessages.length }, null, 2));
  } finally {
    server.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
