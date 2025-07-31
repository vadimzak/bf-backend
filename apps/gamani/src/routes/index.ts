import { Express } from 'express';
import { authRoutes } from './auth.routes';
import { protectedRoutes } from './protected.routes';
import { publicRoutes } from './public.routes';
import { authenticateCognito } from '../middleware';

export function setupRoutes(app: Express): void {
  app.use('/api/auth', authRoutes);
  app.use('/api/protected', authenticateCognito, protectedRoutes);
  app.use('/api', publicRoutes);
  app.use('/', publicRoutes);
}