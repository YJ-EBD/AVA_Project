class HttpError extends Error {
  constructor(status, code, message, details = null) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

function badRequest(message, details = null) {
  return new HttpError(400, 'BAD_REQUEST', message, details);
}

function unauthorized(message = 'Authentication is required.') {
  return new HttpError(401, 'UNAUTHORIZED', message);
}

function forbidden(message = 'Access is denied.') {
  return new HttpError(403, 'FORBIDDEN', message);
}

function notFound(message = 'Resource not found.') {
  return new HttpError(404, 'NOT_FOUND', message);
}

function conflict(message, details = null) {
  return new HttpError(409, 'CONFLICT', message, details);
}

function asyncHandler(handler) {
  return (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
}

function errorHandler(error, req, res, next) {
  if (res.headersSent) {
    return next(error);
  }
  const status = error instanceof HttpError ? error.status : 500;
  const code = error instanceof HttpError ? error.code : 'INTERNAL_SERVER_ERROR';
  const message = error instanceof HttpError ? error.message : 'Internal server error.';
  if (!(error instanceof HttpError)) {
    console.error(error);
  }
  res.status(status).json({
    timestamp: new Date().toISOString(),
    status,
    code,
    message,
    path: req.originalUrl || req.url,
    details: error.details || null
  });
}

module.exports = {
  HttpError,
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  asyncHandler,
  errorHandler
};
