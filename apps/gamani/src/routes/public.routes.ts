import { Router, Request, Response } from 'express';
import path from 'path';
import { HealthController, GameController } from '../controllers';

const router = Router();

router.get('/', (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', '..', '..', '..', '..', 'client', 'dist', 'index.html'));
});

router.get('/health', HealthController.getHealth);

router.get('/games/:shareId', GameController.getSharedGame);

router.get('*', (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', '..', '..', '..', '..', 'client', 'dist', 'index.html'));
});

export { router as publicRoutes };