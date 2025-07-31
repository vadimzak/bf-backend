import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { SecretsManagerClient } from '@aws-sdk/client-secrets-manager';
import { createLogger } from '../utils/logger';

const logger = createLogger('AWS CONFIG');

export const awsRegion = process.env.AWS_REGION || 'il-central-1';

logger.debug('Initializing AWS SDK v3 clients');
logger.debug('Region:', awsRegion);

if (process.env.NODE_ENV !== 'production') {
  logger.debug('Development mode - using environment credentials');
} else {
  logger.debug('Production mode - using IRSA credentials');
  if (process.env.AWS_ROLE_ARN && process.env.AWS_WEB_IDENTITY_TOKEN_FILE) {
    logger.success('IRSA environment variables detected');
    logger.debug('Role ARN:', process.env.AWS_ROLE_ARN);
  }
}

export const dynamoClient = new DynamoDBClient({ region: awsRegion });
export const secretsManagerClient = new SecretsManagerClient({ region: awsRegion });

export const dynamodb = DynamoDBDocumentClient.from(dynamoClient, {
  marshallOptions: {
    convertEmptyValues: false,
    removeUndefinedValues: true,
    convertClassInstanceToMap: false,
  },
  unmarshallOptions: {
    wrapNumbers: false,
  },
});

logger.success('SDK v3 clients initialized');