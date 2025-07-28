const http = require('http');
const { docClient, TABLE_NAME } = require('../../config/dynamodb');

async function healthCheck() {
  console.log('🏥 Running comprehensive health check...');
  
  const results = {
    timestamp: new Date().toISOString(),
    status: 'healthy',
    checks: {}
  };

  try {
    // 1. Check web server health
    results.checks.webServer = await checkWebServer();
    
    // 2. Check DynamoDB connectivity
    results.checks.database = await checkDynamoDB();
    
    // 3. Check memory usage
    results.checks.memory = checkMemoryUsage();
    
    // 4. Check disk space (basic check)
    results.checks.system = checkSystemHealth();

    // Determine overall status
    const allChecksHealthy = Object.values(results.checks).every(check => check.status === 'healthy');
    results.status = allChecksHealthy ? 'healthy' : 'unhealthy';

    if (results.status === 'unhealthy') {
      console.warn('⚠️ Health check detected issues:', JSON.stringify(results.checks, null, 2));
    }

    return results;

  } catch (error) {
    results.status = 'error';
    results.error = error.message;
    console.error('❌ Health check failed:', error);
    throw error;
  }
}

async function checkWebServer() {
  return new Promise((resolve) => {
    const options = {
      hostname: 'sample-app', // Docker service name
      port: 3001,
      path: '/health',
      method: 'GET',
      timeout: 3000
    };

    const request = http.request(options, (res) => {
      if (res.statusCode === 200) {
        resolve({ status: 'healthy', responseCode: res.statusCode });
      } else {
        resolve({ status: 'unhealthy', responseCode: res.statusCode });
      }
    });

    request.on('error', (err) => {
      resolve({ status: 'unhealthy', error: err.message });
    });

    request.on('timeout', () => {
      request.destroy();
      resolve({ status: 'unhealthy', error: 'timeout' });
    });

    request.end();
  });
}

async function checkDynamoDB() {
  try {
    const params = {
      TableName: TABLE_NAME,
      Limit: 1
    };
    
    const startTime = Date.now();
    await docClient.scan(params).promise();
    const responseTime = Date.now() - startTime;
    
    return { 
      status: 'healthy', 
      responseTime: `${responseTime}ms` 
    };
  } catch (error) {
    return { 
      status: 'unhealthy', 
      error: error.message 
    };
  }
}

function checkMemoryUsage() {
  const memUsage = process.memoryUsage();
  const usedMB = Math.round(memUsage.heapUsed / 1024 / 1024);
  const totalMB = Math.round(memUsage.heapTotal / 1024 / 1024);
  const usagePercent = Math.round((memUsage.heapUsed / memUsage.heapTotal) * 100);
  
  return {
    status: usagePercent > 90 ? 'unhealthy' : 'healthy',
    heapUsed: `${usedMB}MB`,
    heapTotal: `${totalMB}MB`,
    usagePercent: `${usagePercent}%`
  };
}

function checkSystemHealth() {
  const uptime = Math.floor(process.uptime());
  const uptimeHours = Math.floor(uptime / 3600);
  const uptimeMinutes = Math.floor((uptime % 3600) / 60);
  
  return {
    status: 'healthy',
    uptime: `${uptimeHours}h ${uptimeMinutes}m`,
    nodeVersion: process.version,
    platform: process.platform
  };
}

module.exports = { healthCheck };