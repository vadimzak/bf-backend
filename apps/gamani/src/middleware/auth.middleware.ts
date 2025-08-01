import { Response, NextFunction } from 'express';
import { jwtVerifier } from '../config/cognito';
import { AuthenticatedRequest } from '../types';
import { createLogger } from '../utils/logger';
import { authenticateMock, isMockAuthEnabled } from './mock-auth.middleware';

const logger = createLogger('AUTH MIDDLEWARE');

export const authenticateCognito = async (req: AuthenticatedRequest, res: Response, next: NextFunction): Promise<void> => {
  // Use mock authentication if enabled and headers indicate mock request
  if (isMockAuthEnabled() && (req.headers.authorization?.startsWith('Mock ') || req.headers['x-mock-user'])) {
    logger.auth('Using mock authentication');
    return authenticateMock(req, res, next);
  }
  
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'No valid authorization header' });
    return;
  }

  try {
    const accessToken = authHeader.split('Bearer ')[1];
    const payload = await jwtVerifier.verify(accessToken);
    
    logger.success('Cognito token verified for user:', payload.sub);
    
    req.user = {
      sub: payload.sub as string,
      username: (payload.username as string) || (payload['cognito:username'] as string) || '',
      email: payload.email as string | undefined,
      email_verified: payload.email_verified as boolean | undefined,
      'cognito:username': payload['cognito:username'] as string | undefined
    };
    next();
  } catch (error: any) {
    logger.error('Cognito auth failed:', error.message);
    res.status(401).json({ error: 'Invalid authentication token' });
  }
};