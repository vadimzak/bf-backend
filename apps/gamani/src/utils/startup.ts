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
    await initializeGoogleAI();
    
    logger.success('All critical services initialized successfully');
  } catch (error) {
    logger.error('Critical service initialization failed:', error);
    logger.error('Server startup aborted due to service initialization failure');
    throw error;
  }
}