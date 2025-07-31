import { Response, NextFunction } from 'express';
import { jwtVerifier } from '../config/cognito';
import { AuthenticatedRequest } from '../types';
import { createLogger } from '../utils/logger';

const logger = createLogger('AUTH MIDDLEWARE');

export const authenticateCognito = async (req: AuthenticatedRequest, res: Response, next: NextFunction): Promise<void> => {
  logger.auth(`Cognito authentication attempt for ${req.method} ${req.path}`);
  
  try {
    const authHeader = req.headers.authorization;
    logger.auth('Authorization header present:', !!authHeader);
    logger.auth('Authorization header starts with Bearer:', authHeader?.startsWith('Bearer ') || false);
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      logger.error('No valid authorization header');
      res.status(401).json({ error: 'No valid authorization header' });
      return;
    }

    const accessToken = authHeader.split('Bearer ')[1];
    logger.auth('Access Token length:', accessToken.length);
    logger.auth('Access Token preview:', accessToken.substring(0, 20) + '...');
    
    logger.auth('Verifying token with Cognito...');
    const payload = await jwtVerifier.verify(accessToken);
    logger.success('Token verification successful');
    logger.success('User details:', { 
      sub: payload.sub, 
      username: payload.username,
      client_id: payload.client_id 
    });
    
    req.user = {
      sub: payload.sub as string,
      username: (payload.username as string) || (payload['cognito:username'] as string) || '',
      email: payload.email as string | undefined,
      email_verified: payload.email_verified as boolean | undefined,
      'cognito:username': payload['cognito:username'] as string | undefined
    };
    next();
  } catch (error: any) {
    logger.error('Cognito auth error:', error);
    logger.error('Error details:', {
      name: error.name,
      message: error.message,
      code: error.code || 'unknown'
    });
    res.status(401).json({ error: 'Invalid authentication token' });
  }
};