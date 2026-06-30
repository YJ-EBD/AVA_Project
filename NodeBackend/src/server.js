const http = require('http');
const path = require('path');
const express = require('express');
const cors = require('cors');
const config = require('./config');
const { ensureCoreSchema } = require('./schema');
const { errorHandler } = require('./errors');
const { StompHub } = require('./realtime/stompHub');
const { ChatService } = require('./services/chatService');
const healthRouter = require('./routes/health');
const { createAuthRouter } = require('./routes/auth');
const usersRouter = require('./routes/users');
const { createChatRouter } = require('./routes/chat');
const notificationsRouter = require('./routes/notifications');
const pushRouter = require('./routes/push');
const appUpdatesRouter = require('./routes/appUpdates');
const adminRouter = require('./routes/admin');
const calendarRouter = require('./routes/calendar');
const { createAzoomRouter } = require('./routes/azoom');
const { createAiRouter } = require('./routes/ai');
const avaStockRouter = require('./routes/avaStock');
const { closePool } = require('./db');

async function main() {
  await ensureCoreSchema();

  const app = express();
  const server = http.createServer(app);
  const realtimeHub = new StompHub();
  const chatService = new ChatService(realtimeHub);
  realtimeHub.setChatService(chatService);
  realtimeHub.attach(server);

  app.disable('x-powered-by');
  app.use(cors({
    origin(origin, callback) {
      if (!origin || config.allowedOrigins.includes('*')) {
        callback(null, true);
        return;
      }
      callback(null, config.allowedOrigins.includes(origin));
    },
    credentials: false
  }));
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true }));

  app.use('/api', healthRouter);
  app.use('/api/auth', createAuthRouter(realtimeHub));
  app.use('/api/users', usersRouter);
  app.use('/api/chat', createChatRouter(chatService));
  app.use('/api/notifications', notificationsRouter);
  app.use('/api/push', pushRouter);
  app.use('/api/app-updates', appUpdatesRouter);
  app.use('/api/admin', adminRouter);
  app.use('/api/calendar', calendarRouter);
  app.use('/api/azoom', createAzoomRouter(realtimeHub));
  app.use('/api/ai', createAiRouter(chatService));
  app.use('/api/ava-stock', avaStockRouter);
  app.get('/rtc/validate', (req, res) => res.json({ valid: true, runtime: 'node' }));

  app.use('/stock', express.static(path.join(config.rootDir, 'AVA_stock')));
  app.use('/ava-stock-web', express.static(path.join(config.rootDir, 'AVA_stock')));
  app.use('/ava-stock-assets', express.static(path.join(config.rootDir, 'AVA_stock')));

  app.use(errorHandler);

  server.listen(config.port, config.host, () => {
    console.log(`[AVA] NodeBackend listening on ${config.host}:${config.port}`);
    console.log(`[AVA] AppUpdates directory: ${config.updateDirectory}`);
  });

  async function shutdown() {
    console.log('[AVA] NodeBackend shutting down.');
    server.close(async () => {
      await closePool();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10000).unref();
  }

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
