import { ScanCommand } from '@aws-sdk/lib-dynamodb';
import { dynamodb } from '../config/aws';
import { initializeGoogleAI } from '../config/google-ai';
import { createLogger } from './logger';

const logger = createLogger('STARTUP');

export async function validateAWSServices(): Promise<void> {
  try {
    logger.debug('Validating AWS service connectivity...');
    
    const listTablesCommand = new ScanCommand({
      TableName: process.env.DYNAMODB_TABLE_NAME || 'gamani-items',
      Limit: 1
    });
    await dynamodb.send(listTablesCommand);
    
    logger.success('DynamoDB connectivity validated');
  } catch (error) {
    logger.error('Failed to validate AWS services:', error);
    throw new Error(`AWS services validation failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

export async function initializeCriticalServices(): Promise<void> {
  logger.debug('Initializing critical services...');
  
  try {
    await validateAWSServices();
    
    // Try to initialize Google AI, but don't fail if it's not available
    try {
      await initializeGoogleAI();
      logger.success('Google AI initialized successfully');
    } catch (googleAIError) {
      logger.warning('Google AI initialization failed, game generation will be disabled:', googleAIError);
      // Don't throw - allow server to start without Google AI for testing other features
    }
    
    logger.success('Critical services initialized (Google AI optional)');
  } catch (error) {
    logger.error('Critical service initialization failed:', error);
    logger.error('Server startup aborted due to service initialization failure');
    throw error;
  }
}