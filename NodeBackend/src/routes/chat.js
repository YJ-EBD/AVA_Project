const express = require('express');
const fs = require('fs');
const path = require('path');
const { randomUUID } = require('crypto');
const multer = require('multer');
const mime = require('mime-types');
const config = require('../config');
const { asyncHandler, notFound } = require('../errors');
const { authRequired } = require('../services/authService');
const { uploadFileName } = require('../utils/uploadNames');

function createChatRouter(chatService) {
  const router = express.Router();
  const uploadDir = path.join(config.backendDir, 'ChatUploads');
  fs.mkdirSync(uploadDir, { recursive: true });
  const upload = multer({ dest: uploadDir });

  router.use(authRequired);

  router.get('/rooms', asyncHandler(async (req, res) => {
    res.json(await chatService.rooms(req.principal, req));
  }));

  router.get('/link-preview', asyncHandler(async (req, res) => {
    const url = String(req.query.url || '');
    res.json({
      url,
      title: url,
      description: '',
      imageUrl: '',
      siteName: ''
    });
  }));

  router.post('/direct-rooms', asyncHandler(async (req, res) => {
    res.json(await chatService.startDirectRoom(req.body, req.principal, req));
  }));

  router.post('/group-rooms', asyncHandler(async (req, res) => {
    res.json(await chatService.startGroupRoom(req.body, req.principal, req));
  }));

  router.post('/self-room', asyncHandler(async (req, res) => {
    res.json(await chatService.startSelfRoom(req.principal, req));
  }));

  router.post('/rooms/:roomCode/members', asyncHandler(async (req, res) => {
    res.json(await chatService.startGroupRoom(req.body, req.principal, req));
  }));

  router.get('/rooms/:roomCode/messages', asyncHandler(async (req, res) => {
    res.json(await chatService.recentMessages(req.params.roomCode, req.principal, req.query.limit));
  }));

  router.get('/rooms/:roomCode/messages/around/:messageId', asyncHandler(async (req, res) => {
    res.json(await chatService.messagesAround(
      req.params.roomCode,
      req.params.messageId,
      req.principal,
      req.query.before,
      req.query.after
    ));
  }));

  router.get('/rooms/:roomCode/messages/before/:messageId', asyncHandler(async (req, res) => {
    res.json(await chatService.messagesBefore(req.params.roomCode, req.params.messageId, req.principal, req.query.limit));
  }));

  router.post('/rooms/:roomCode/messages', asyncHandler(async (req, res) => {
    res.json(await chatService.sendMessage(req.params.roomCode, req.body, req.principal));
  }));

  router.post('/rooms/:roomCode/attachments', upload.single('file'), asyncHandler(async (req, res) => {
    const fileName = req.file ? uploadFileName(req.file) : 'attachment';
    const attachmentId = randomUUID();
    res.json(await chatService.sendMessage(req.params.roomCode, {
      content: fileName,
      silent: false,
      spoiler: false,
      mentions: [],
      attachment: req.file ? {
        id: attachmentId,
        groupId: req.body.groupId || null,
        fileName,
        contentType: req.file.mimetype || mime.lookup(fileName) || 'application/octet-stream',
        size: req.file.size || 0,
        storedPath: req.file.path
      } : null
    }, req.principal));
  }));

  router.get('/rooms/:roomCode/attachments/:attachmentId', asyncHandler(async (req, res) => {
    const attachment = await chatService.attachmentForDownload(req.params.roomCode, req.params.attachmentId, req.principal);
    if (!fs.existsSync(attachment.filePath)) {
      throw notFound('Chat attachment file not found on disk.');
    }
    res.type(attachment.contentType);
    res.download(attachment.filePath, attachment.fileName);
  }));

  router.post('/rooms/:roomCode/messages/:messageId/delete-for-everyone', asyncHandler(async (req, res) => {
    res.json(await chatService.deleteForEveryone(req.params.roomCode, req.params.messageId, req.principal));
  }));

  router.get('/rooms/:roomCode/talk-drawer', asyncHandler(async (req, res) => {
    await chatService.assertMember(req.params.roomCode, req.principal);
    res.json([]);
  }));

  router.post('/rooms/:roomCode/read', asyncHandler(async (req, res) => {
    res.json(await chatService.markRead(req.params.roomCode, req.principal));
  }));

  router.get('/mention-notifications', asyncHandler(async (req, res) => {
    res.json(await chatService.mentionNotifications(req.query.status || 'all', req.principal, req.query.limit));
  }));

  router.post('/mention-notifications/:notificationId/checked', asyncHandler(async (req, res) => {
    res.json(await chatService.markMentionNotificationChecked(req.params.notificationId, req.principal));
  }));

  router.post('/rooms/:roomCode/leave', asyncHandler(async (req, res) => {
    res.json(await chatService.leaveRoom(req.params.roomCode, req.principal));
  }));

  router.put('/rooms/:roomCode/notice', asyncHandler(async (req, res) => {
    res.json(await chatService.setNotice(req.params.roomCode, req.body, req.principal));
  }));

  router.put('/rooms/:roomCode/pin', asyncHandler(async (req, res) => {
    res.json(await chatService.setPinned(req.params.roomCode, req.body, req.principal));
  }));

  return router;
}

module.exports = {
  createChatRouter
};
