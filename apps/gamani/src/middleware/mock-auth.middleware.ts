import { Response, NextFunction } from 'express';
import { AuthenticatedRequest } from '../types';
import { createLogger } from '../utils/logger';

const logger = createLogger('MOCK AUTH MIDDLEWARE');

// Test user personas for different authentication scenarios
export const TEST_USERS = {
  admin: { sub: 'mock-admin-user-123', username: 'admin_user', email: 'admin@test.com', email_verified: true, 'cognito:username': 'admin_user' },
  user: { sub: 'mock-regular-user-456', username: 'regular_user', email: 'user@test.com', email_verified: true, 'cognito:username': 'regular_user' },
  unverified: { sub: 'mock-unverified-user-789', username: 'unverified_user', email: 'unverified@test.com', email_verified: false, 'cognito:username': 'unverified_user' },
  minimal: { sub: 'mock-minimal-user-012', username: 'minimal_user', email: undefined, email_verified: undefined, 'cognito:username': 'minimal_user' },
  newbie: { sub: 'mock-new-user-345', username: 'new_user', email: 'newuser@test.com', email_verified: true, 'cognito:username': 'new_user' }
} as const;

export type TestUserType = keyof typeof TEST_USERS;

export const isMockAuthEnabled = (): boolean => {
  return process.env.NODE_ENV === 'development' && 
         (process.env.ENABLE_AUTH_MOCKING === 'true' || process.env.PLAYWRIGHT_TEST === 'true');
};

const getCurrentMockUser = (req: AuthenticatedRequest): typeof TEST_USERS[TestUserType] => {
  // Extract user type from "Mock user_type" header or "X-Mock-User" header
  const authHeader = req.headers.authorization?.split('Mock ')[1] as TestUserType;
  const mockUserHeader = req.headers['x-mock-user'] as TestUserType;
  const userType = authHeader || mockUserHeader;
  
  return TEST_USERS[userType] || TEST_USERS.user; // Default to 'user' if invalid/missing
};

export const authenticateMock = async (req: AuthenticatedRequest, res: Response, next: NextFunction): Promise<void> => {
  if (!isMockAuthEnabled()) {
    res.status(500).json({ error: 'Mock authentication not available' });
    return;
  }

  try {
    const mockUser = getCurrentMockUser(req);
    logger.auth(`Mock authentication for ${req.method} ${req.path}`);
    logger.success('Mock authentication successful');
    logger.success('Mock user:', { sub: mockUser.sub, username: mockUser.username, email: mockUser.email });
    
    req.user = mockUser;
    next();
  } catch (error) {
    logger.error('Mock auth error:', error);
    res.status(500).json({ error: 'Mock authentication failed' });
  }
};

export const logMockAuthStatus = (): void => {
  if (isMockAuthEnabled()) {
    logger.success('🎭 MOCK AUTHENTICATION ENABLED - Development/Testing Mode');
    logger.success('Available test users:', Object.keys(TEST_USERS).join(', '));
    logger.success('Set Authorization: "Mock <user_type>" or X-Mock-User: <user_type> header');
  }
};