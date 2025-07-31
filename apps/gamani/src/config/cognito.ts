import { CognitoJwtVerifier } from 'aws-jwt-verify';
import { createLogger } from '../utils/logger';

const logger = createLogger('COGNITO CONFIG');

export const jwtVerifier = CognitoJwtVerifier.create({
  userPoolId: 'il-central-1_aJg6S7Rl3',
  tokenUse: 'access',
  clientId: '1qa3m3ok5i8ehg0ef8jg3fnff6',
});

logger.success('JWT Verifier initialized');