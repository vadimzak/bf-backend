import { Request, Response } from 'express';
import { createApiResponse, getAppInfo, formatUptime, serverCore } from '@bf-backend/server-core';
import { jwtVerifier } from '../config/cognito';
import { dynamodb } from '../config/aws';
import { isGoogleAIInitialized } from '../config/google-ai';
import { HealthData } from '../types';

export class HealthController {
  static async getHealth(req: Request, res: Response): Promise<void> {
    const version = process.env.APP_VERSION || '1.0.0';
    const appInfo = getAppInfo('gamani', version);
    
    const healthData: HealthData = {
      ...appInfo,
      status: 'healthy',
      uptimeFormatted: formatUptime(appInfo.uptime),
      version: version,
      gitCommit: process.env.APP_GIT_COMMIT || 'unknown',
      buildTime: process.env.APP_BUILD_TIME || 'unknown',
      deployedBy: process.env.APP_DEPLOYED_BY || 'unknown',
      serverCore: serverCore(),
      services: {
        cognito: !!jwtVerifier,
        dynamodb: !!dynamodb,
        googleAI: isGoogleAIInitialized()
      }
    };
    
    res.json(createApiResponse(healthData, 'Health check successful'));
  }
}