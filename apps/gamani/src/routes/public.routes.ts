import { Router, Request, Response } from 'express';
import path from 'path';
import express from 'express';
import { HealthController, GameController } from '../controllers';

const router = Router();

// Serve static files from client dist directory
router.use('/assets', express.static(path.join(__dirname, '..', '..', 'client', 'dist', 'assets')));
router.use('/manifest.json', express.static(path.join(__dirname, '..', '..', 'client', 'dist', 'manifest.json')));
router.use('/vite.svg', express.static(path.join(__dirname, '..', '..', 'client', 'dist', 'vite.svg')));

router.get('/', (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', '..', 'client', 'dist', 'index.html'));
});

router.get('/health', HealthController.getHealth);

router.get('/games/:shareId', GameController.getSharedGame);

// Catch-all route for client-side routing (SPA)
router.get('*', (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', '..', 'client', 'dist', 'index.html'));
});

export { router as publicRoutes };