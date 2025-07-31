import { Express } from 'express';
import express from 'express';
import path from 'path';
import { authRoutes } from './auth.routes';
import { protectedRoutes } from './protected.routes';
import { publicRoutes } from './public.routes';
import { authenticateCognito } from '../middleware';

export function setupRoutes(app: Express): void {
  app.use('/api/auth', authRoutes);
  app.use('/api/protected', authenticateCognito, protectedRoutes);
  
  // Serve static assets from client/dist BEFORE any catch-all routes
  const clientDistPath = path.join(__dirname, '..', '..', '..', '..', '..', 'client', 'dist');
  app.use(express.static(clientDistPath));
  
  // Mount public routes at root level (includes /health, /games/:shareId, and SPA catch-all)
  app.use('/', publicRoutes);
}