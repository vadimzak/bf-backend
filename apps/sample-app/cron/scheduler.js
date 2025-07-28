const cron = require('node-cron');
require('dotenv').config();

// Import task modules
const { cleanupOldRecords } = require('./tasks/cleanup');
const { generateReports } = require('./tasks/reports');
const { healthCheck } = require('./tasks/health');

console.log('🚀 Starting scheduled task runner...');
console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);

// Health check every 5 minutes
cron.schedule('*/5 * * * *', async () => {
  console.log('Running health check...');
  try {
    await healthCheck();
    console.log('✅ Health check completed');
  } catch (error) {
    console.error('❌ Health check failed:', error.message);
  }
});

// Cleanup old records daily at 2 AM
cron.schedule('0 2 * * *', async () => {
  console.log('Running daily cleanup...');
  try {
    await cleanupOldRecords();
    console.log('✅ Daily cleanup completed');
  } catch (error) {
    console.error('❌ Daily cleanup failed:', error.message);
  }
});

// Generate reports weekly on Sundays at 3 AM
cron.schedule('0 3 * * 0', async () => {
  console.log('Running weekly reports...');
  try {
    await generateReports();
    console.log('✅ Weekly reports completed');
  } catch (error) {
    console.error('❌ Weekly reports failed:', error.message);
  }
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('📡 Received SIGTERM, shutting down gracefully...');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('📡 Received SIGINT, shutting down gracefully...');
  process.exit(0);
});

console.log('📅 Scheduled tasks are now running...');