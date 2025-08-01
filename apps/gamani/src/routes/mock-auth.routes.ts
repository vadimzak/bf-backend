import { Router, Request, Response } from 'express';
import { createApiResponse } from '@bf-backend/server-core';
import { TEST_USERS, TestUserType, isMockAuthEnabled } from '../middleware/mock-auth.middleware';

const router = Router();

// Ensure mock auth is enabled for all routes
router.use((req, res, next) => {
  if (!isMockAuthEnabled()) {
    res.status(404).json({ error: 'Mock authentication not available' });
    return;
  }
  next();
});

router.get('/users', (req: Request, res: Response) => {
  const users = Object.entries(TEST_USERS).map(([key, user]) => ({
    type: key,
    username: user.username,
    email: user.email,
    email_verified: user.email_verified
  }));
  res.json(createApiResponse(users, 'Available test users'));
});

router.post('/login/:userType', (req: Request, res: Response) => {
  const { userType } = req.params as { userType: TestUserType };
  
  if (!(userType in TEST_USERS)) {
    res.status(400).json({ 
      error: 'Invalid user type', 
      availableTypes: Object.keys(TEST_USERS) 
    });
    return;
  }
  
  res.json(createApiResponse({
    user: TEST_USERS[userType],
    authHeaders: { 'Authorization': `Mock ${userType}`, 'X-Mock-User': userType }
  }, `Logged in as ${userType}`));
});

router.get('/current-user', (req: Request, res: Response) => {
  const authHeader = req.headers.authorization?.split('Mock ')[1] as TestUserType;
  const mockUserHeader = req.headers['x-mock-user'] as TestUserType;
  const userType = authHeader || mockUserHeader;
  const currentUser = userType && TEST_USERS[userType];
  
  res.json(createApiResponse({
    userType: userType || null,
    user: currentUser || null,
    authenticated: !!currentUser
  }, currentUser ? 'Current mock user' : 'No mock user set'));
});

router.post('/logout', (req: Request, res: Response) => {
  res.json(createApiResponse({ authenticated: false }, 'Logged out'));
});

router.get('/health', (req: Request, res: Response) => {
  res.json(createApiResponse({
    mockAuthEnabled: isMockAuthEnabled(),
    availableUsers: Object.keys(TEST_USERS)
  }, 'Mock auth system health'));
});

export { router as mockAuthRoutes };