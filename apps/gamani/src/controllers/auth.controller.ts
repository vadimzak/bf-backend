import { Response } from 'express';
import { createApiResponse } from '@bf-backend/server-core';
import { AuthenticatedRequest } from '../types';
import { AuthService } from '../services';

export class AuthController {
  static async verify(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userData = await AuthService.verifyUser(req);
      res.json(createApiResponse(userData, 'User authenticated successfully'));
    } catch (error) {
      res.status(500).json({ error: 'Authentication verification failed' });
    }
  }
}