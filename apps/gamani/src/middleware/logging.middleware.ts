import { Request, Response, NextFunction } from 'express';
import { createLogger } from '../utils/logger';

const logger = createLogger('SERVER REQUEST');

export const requestLogging = (req: Request, res: Response, next: NextFunction) => {
  if (req.path !== '/health') {
    logger.request(`${req.method} ${req.path}`);
    if (req.headers.authorization) {
      logger.request(`Has authorization header: ${req.headers.authorization.substring(0, 20)}...`);
    }
  }
  next();
};