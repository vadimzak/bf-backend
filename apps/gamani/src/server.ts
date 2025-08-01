import express from 'express';
import dotenv from 'dotenv';
import { configureSecurityMiddleware, requestLogging, errorHandler } from './middleware';
import { setupRoutes } from './routes';
import { initializeCriticalServices } from './utils/startup';
import { createLogger } from './utils/logger';
import { logMockAuthStatus } from './middleware/mock-auth.middleware';

dotenv.config();

const logger = createLogger('SERVER');
const app = express();
const PORT = process.env.PORT || 3002;

configureSecurityMiddleware(app);
app.use(requestLogging);

setupRoutes(app);

app.use(errorHandler);

async function startServer(): Promise<void> {
  try {
    await initializeCriticalServices();
    
    app.listen(PORT, () => {
      const version = process.env.APP_VERSION || '1.0.0';
      const gitCommit = process.env.APP_GIT_COMMIT || 'unknown';
      const buildTime = process.env.APP_BUILD_TIME || 'unknown';
      const deployedBy = process.env.APP_DEPLOYED_BY || 'unknown';
      
      logger.startup(`Gamani app v${version} listening on port ${PORT}`);
      logger.startup(`Environment: ${process.env.NODE_ENV || 'development'}`);
      logger.debug(`Git commit: ${gitCommit}`);
      logger.debug(`Build time: ${buildTime}`);
      logger.debug(`Deployed by: ${deployedBy}`);
      logger.success('All services initialized successfully');
      logMockAuthStatus();
    });
  } catch (error) {
    logger.error('Failed to start server due to initialization errors');
    process.exit(1);
  }
}

startServer();