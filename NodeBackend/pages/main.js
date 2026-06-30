const express = require('express');
const path = require('path');
const config = require('../src/config');

const pagesDir = __dirname;
const templatesDir = path.resolve(config.backendDir, 'templates');
const staticDir = path.resolve(config.backendDir, 'static');

function createPagesRouter() {
  const router = express.Router();

  router.use('/static', express.static(staticDir, {
    etag: true,
    fallthrough: true,
    maxAge: '1h'
  }));

  router.get('/', (req, res) => {
    res.sendFile(path.join(templatesDir, 'index.html'));
  });

  router.get('/index.html', (req, res) => {
    res.redirect(301, '/');
  });

  return router;
}

module.exports = {
  createPagesRouter,
  pagesDir,
  staticDir,
  templatesDir
};
