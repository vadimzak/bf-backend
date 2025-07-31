import { AuthenticatedRequest } from '../types';
import { createLogger } from '../utils/logger';

const logger = createLogger('AUTH SERVICE');

export class AuthService {
  static async verifyUser(req: AuthenticatedRequest) {
    logger.success('/api/auth/verify - User authenticated successfully');
    const userData = {
      sub: req.user?.sub,
      username: req.user?.username,
      email: req.user?.email,
      email_verified: req.user?.email_verified
    };
    logger.success('Returning user data:', userData);
    return userData;
  }
}