import { GoogleGenAI } from '@google/genai';
import { GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { secretsManagerClient } from './aws';
import { createLogger } from '../utils/logger';

const logger = createLogger('GOOGLE AI CONFIG');

let genAI: GoogleGenAI;

export async function initializeGoogleAI(): Promise<void> {
  try {
    logger.debug('Fetching API key from Secrets Manager...');
    const command = new GetSecretValueCommand({
      SecretId: 'gamani/google-ai-api-key'
    });
    const result = await secretsManagerClient.send(command);
    
    const apiKey = result.SecretString;
    if (!apiKey || apiKey === 'PLACEHOLDER_KEY_NEEDS_UPDATE') {
      throw new Error('Google AI API key is missing or placeholder. Game generation cannot function without valid API key.');
    }
    
    genAI = new GoogleGenAI({
      apiKey: apiKey
    });
    logger.success('Initialized successfully');
  } catch (error) {
    logger.error('Failed to initialize Google AI service:', error);
    throw error;
  }
}

export function getGoogleAI(): GoogleGenAI {
  if (!genAI) {
    throw new Error('Google AI not initialized. Call initializeGoogleAI() first.');
  }
  return genAI;
}

export function isGoogleAIInitialized(): boolean {
  return !!genAI;
}