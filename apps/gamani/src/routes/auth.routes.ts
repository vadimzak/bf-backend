import { Router } from 'express';
import { AuthController } from '../controllers';
import { authenticateCognito } from '../middleware';

const router = Router();

router.post('/verify', authenticateCognito, AuthController.verify);

export { router as authRoutes };