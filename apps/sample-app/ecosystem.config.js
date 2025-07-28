module.exports = {
  apps: [{
    name: 'sample-app',
    script: './server.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '512M',
    env: {
      NODE_ENV: 'production',
      PORT: 3001
    },
    error_file: '/var/log/pm2/sample-app-error.log',
    out_file: '/var/log/pm2/sample-app-out.log',
    log_file: '/var/log/pm2/sample-app-combined.log',
    time: true
  }]
};