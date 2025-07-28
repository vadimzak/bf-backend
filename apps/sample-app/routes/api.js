const express = require('express');
const router = express.Router();

// GET /api
router.get('/', (req, res) => {
  res.json({
    message: 'Welcome to Sample App API',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      items: '/api/items',
      info: '/api/info'
    }
  });
});

// GET /api/info
router.get('/info', (req, res) => {
  res.json({
    app: 'Sample NodeJS Application',
    domain: 'sample.vadimzak.com',
    environment: process.env.NODE_ENV || 'development',
    timestamp: new Date().toISOString()
  });
});

// GET /api/stats
router.get('/stats', (req, res) => {
  res.json({
    uptime: process.uptime(),
    memory: process.memoryUsage(),
    nodeVersion: process.version
  });
});

module.exports = router;