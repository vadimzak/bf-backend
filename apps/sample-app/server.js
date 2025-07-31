const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const path = require('path');
const { serverCore } = require('@bf-backend/server-core');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static('public'));

// Routes
const apiRoutes = require('./routes/api');
const dynamoRoutes = require('./routes/dynamo');

// API Routes
app.use('/api', apiRoutes);
app.use('/api/items', dynamoRoutes);

// Home route
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Health check
app.get('/health', (req, res) => {
  const version = process.env.APP_VERSION || '1.0.0';
  res.json({ 
    status: 'healthy',
    service: 'sample-app',
    timestamp: new Date().toISOString(),
    version: version,
    gitCommit: process.env.APP_GIT_COMMIT || 'unknown',
    buildTime: process.env.APP_BUILD_TIME || 'unknown',
    deployedBy: process.env.APP_DEPLOYED_BY || 'unknown',
    serverCore: serverCore()
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start server
app.listen(PORT, () => {
  const version = process.env.APP_VERSION || '1.0.0';
  const gitCommit = process.env.APP_GIT_COMMIT || 'unknown';
  const buildTime = process.env.APP_BUILD_TIME || 'unknown';
  const deployedBy = process.env.APP_DEPLOYED_BY || 'unknown';
  
  console.log(`🚀 Sample app v${version} listening on port ${PORT}`);
  console.log(`📦 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`📦 Git commit: ${gitCommit}`);
  console.log(`📦 Build time: ${buildTime}`);
  console.log(`📦 Deployed by: ${deployedBy}`);
});