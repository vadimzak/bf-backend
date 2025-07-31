import express, { Request, Response, NextFunction } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import { serverCore, getAppInfo, formatUptime, createApiResponse, createErrorResponse, AppInfo } from '@bf-backend/server-core';
import dotenv from 'dotenv';

// AWS JWT Verify for Cognito
import { CognitoJwtVerifier } from 'aws-jwt-verify';

// AWS SDK v3 for DynamoDB and Secrets Manager
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, PutCommand, GetCommand, UpdateCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

// Google Generative AI
import { GoogleGenAI } from '@google/genai';

dotenv.config();

// Utility function for timestamped logging
const timestamp = () => new Date().toISOString();
const log = (level: string, message: string, ...args: any[]) => {
  console.log(`[${timestamp()}] ${level} ${message}`, ...args);
};

// Types
interface AuthenticatedRequest extends Request {
  user?: {
    sub: string;
    username: string;
    email?: string;
    email_verified?: boolean;
    'cognito:username'?: string;
  };
}

interface CreateItemRequest {
  title: string;
  content: string;
}

interface CreateProjectRequest {
  name: string;
  description?: string;
}

interface UpdateProjectRequest {
  name?: string;
  description?: string;
}

interface CreateMessageRequest {
  role: 'user' | 'assistant';
  content: string;
  gameCode?: string;
}

interface AIGenerateRequest {
  prompt: string;
  conversation?: Array<{
    role: 'user' | 'assistant';
    content: string;
  }>;
  currentGame?: string;
}

const app = express();
const PORT = process.env.PORT || 3002;

// AWS SDK v3 Configuration
const awsRegion = process.env.AWS_REGION || 'il-central-1';

// AWS SDK v3 automatically picks up IRSA credentials when environment variables are present
log('🔧 [AWS]', 'Initializing AWS SDK v3 clients');
log('🔧 [AWS]', 'Region:', awsRegion);

if (process.env.NODE_ENV !== 'production') {
  log('🔧 [AWS]', 'Development mode - using environment credentials');
} else {
  log('🔧 [AWS]', 'Production mode - using IRSA credentials');
  if (process.env.AWS_ROLE_ARN && process.env.AWS_WEB_IDENTITY_TOKEN_FILE) {
    log('✅ [AWS]', 'IRSA environment variables detected');
    log('🔧 [AWS]', 'Role ARN:', process.env.AWS_ROLE_ARN);
  }
}

// Initialize AWS SDK v3 clients
const dynamoClient = new DynamoDBClient({ region: awsRegion });
const secretsManagerClient = new SecretsManagerClient({ region: awsRegion });

log('✅ [AWS]', 'SDK v3 clients initialized');

// Initialize Cognito JWT Verifier
const jwtVerifier = CognitoJwtVerifier.create({
  userPoolId: 'il-central-1_aJg6S7Rl3',
  tokenUse: 'access',
  clientId: '1qa3m3ok5i8ehg0ef8jg3fnff6',
});

log('✅ [COGNITO]', 'JWT Verifier initialized');

// Initialize DynamoDB Document Client (AWS SDK v3)
const dynamodb = DynamoDBDocumentClient.from(dynamoClient, {
  marshallOptions: {
    convertEmptyValues: false,
    removeUndefinedValues: true,
    convertClassInstanceToMap: false,
  },
  unmarshallOptions: {
    wrapNumbers: false,
  },
});

// Initialize Google Generative AI (will be set after fetching from Secrets Manager)
let genAI: GoogleGenAI;

// Function to initialize Google AI with API key from Secrets Manager
async function initializeGoogleAI(): Promise<void> {
  try {
    log('🔐 [GOOGLE AI]', 'Fetching API key from Secrets Manager...');
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
    log('✅ [GOOGLE AI]', 'Initialized successfully');
  } catch (error) {
    log('❌ [GOOGLE AI]', 'Failed to initialize Google AI service:', error);
    throw error; // Re-throw to fail server startup
  }
}

// Function to validate AWS connectivity
async function validateAWSServices(): Promise<void> {
  try {
    log('🔄 [AWS]', 'Validating AWS service connectivity...');
    
    // Test DynamoDB connectivity by listing tables (or checking one specific table)
    const listTablesCommand = new ScanCommand({
      TableName: process.env.DYNAMODB_TABLE_NAME || 'gamani-items',
      Limit: 1 // Just test connectivity, don't fetch data
    });
    await dynamodb.send(listTablesCommand);
    
    log('✅ [AWS]', 'DynamoDB connectivity validated');
  } catch (error) {
    log('❌ [AWS]', 'Failed to validate AWS services:', error);
    throw new Error(`AWS services validation failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

// Function to initialize all critical services
async function initializeCriticalServices(): Promise<void> {
  log('🔄 [STARTUP]', 'Initializing critical services...');
  
  try {
    // Validate AWS services connectivity
    await validateAWSServices();
    
    // Initialize Google AI (critical for core functionality)
    await initializeGoogleAI();
    
    log('✅ [STARTUP]', 'All critical services initialized successfully');
  } catch (error) {
    log('❌ [STARTUP]', 'Critical service initialization failed:', error);
    log('💥 [STARTUP]', 'Server startup aborted due to service initialization failure');
    process.exit(1); // Fail fast - exit the process
  }
}

// Middleware - Disable CSP completely to allow Firebase auth
app.use(helmet({
  contentSecurityPolicy: false
}));

app.use(cors({
  origin: process.env.NODE_ENV === 'production' 
    ? ['https://gamani.vadimzak.com'] 
    : ['http://localhost:5173', 'http://localhost:3000', 'http://localhost:3002'],
  credentials: true
}));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(express.static(path.join(__dirname, '..', '..', '..', '..', 'client', 'dist')));

// Request logging middleware
app.use((req: Request, res: Response, next: NextFunction) => {
  log('📡 [SERVER REQUEST]', `${req.method} ${req.path}`);
  if (req.headers.authorization) {
    log('📡 [SERVER REQUEST]', `Has authorization header: ${req.headers.authorization.substring(0, 20)}...`);
  }
  next();
});

// Cognito Auth middleware
const authenticateCognito = async (req: AuthenticatedRequest, res: Response, next: NextFunction): Promise<void> => {
  log('🔐 [SERVER AUTH]', `Cognito authentication attempt for ${req.method} ${req.path}`);
  
  try {
    const authHeader = req.headers.authorization;
    log('🔐 [SERVER AUTH]', 'Authorization header present:', !!authHeader);
    log('🔐 [SERVER AUTH]', 'Authorization header starts with Bearer:', authHeader?.startsWith('Bearer ') || false);
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      log('❌ [SERVER AUTH]', 'No valid authorization header');
      res.status(401).json({ error: 'No valid authorization header' });
      return;
    }

    const accessToken = authHeader.split('Bearer ')[1];
    log('🔐 [SERVER AUTH]', 'Access Token length:', accessToken.length);
    log('🔐 [SERVER AUTH]', 'Access Token preview:', accessToken.substring(0, 20) + '...');
    
    log('🔐 [SERVER AUTH]', 'Verifying token with Cognito...');
    const payload = await jwtVerifier.verify(accessToken);
    log('✅ [SERVER AUTH]', 'Token verification successful');
    log('✅ [SERVER AUTH]', 'User details:', { 
      sub: payload.sub, 
      username: payload.username,
      client_id: payload.client_id 
    });
    
    req.user = {
      sub: payload.sub as string,
      username: (payload.username as string) || (payload['cognito:username'] as string) || '',
      email: payload.email as string | undefined,
      email_verified: payload.email_verified as boolean | undefined,
      'cognito:username': payload['cognito:username'] as string | undefined
    };
    next();
  } catch (error: any) {
    log('❌ [SERVER AUTH]', 'Cognito auth error:', error);
    log('❌ [SERVER AUTH]', 'Error details:', {
      name: error.name,
      message: error.message,
      code: error.code || 'unknown'
    });
    res.status(401).json({ error: 'Invalid authentication token' });
  }
};

// Routes

// Public routes
app.get('/', (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', '..', '..', '..', 'client', 'dist', 'index.html'));
});

// Health check
app.get('/health', (req: Request, res: Response) => {
  const version = process.env.APP_VERSION || '1.0.0';
  const appInfo = getAppInfo('gamani', version);
  const healthData = {
    ...appInfo,
    status: 'healthy',
    uptimeFormatted: formatUptime(appInfo.uptime),
    version: version,
    gitCommit: process.env.APP_GIT_COMMIT || 'unknown',
    buildTime: process.env.APP_BUILD_TIME || 'unknown',
    deployedBy: process.env.APP_DEPLOYED_BY || 'unknown',
    serverCore: serverCore(),
    services: {
      cognito: !!jwtVerifier,
      dynamodb: !!dynamodb,
      googleAI: !!genAI
    }
  };
  
  res.json(createApiResponse(healthData, 'Health check successful'));
});

// Auth routes
app.post('/api/auth/verify', authenticateCognito, (req: AuthenticatedRequest, res: Response) => {
  log('✅ [SERVER AUTH]', '/api/auth/verify - User authenticated successfully');
  const userData = {
    sub: req.user?.sub,
    username: req.user?.username,
    email: req.user?.email,
    email_verified: req.user?.email_verified
  };
  log('✅ [SERVER AUTH]', 'Returning user data:', userData);
  res.json(createApiResponse(userData, 'User authenticated successfully'));
});

// Protected API routes
app.use('/api/protected', authenticateCognito);

// DynamoDB routes
app.get('/api/protected/items', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  log('🔍 [ITEMS API]', 'GET /api/protected/items - Starting');
  log('🔍 [ITEMS API]', 'User sub:', req.user?.sub);
  log('🔍 [ITEMS API]', 'Table name:', process.env.DYNAMODB_TABLE_NAME || 'gamani-items');
  
  try {
    const params = {
      TableName: process.env.DYNAMODB_TABLE_NAME || 'gamani-items',
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': req.user?.sub
      }
    };

    log('🔍 [ITEMS API]', 'DynamoDB params:', JSON.stringify(params, null, 2));
    log('🔍 [ITEMS API]', 'About to call dynamodb.scan()...');
    
    const command = new ScanCommand(params);
    const result = await dynamodb.send(command);
    
    log('✅ [ITEMS API]', 'DynamoDB scan completed successfully');
    log('✅ [ITEMS API]', 'Result:', JSON.stringify(result, null, 2));
    
    res.json(createApiResponse({ items: result.Items }, 'Items retrieved successfully'));
    log('✅ [ITEMS API]', 'Response sent successfully');
  } catch (error) {
    log('❌ [ITEMS API]', 'DynamoDB error:', error);
    res.status(500).json(createErrorResponse('Failed to fetch items'));
    log('❌ [ITEMS API]', 'Error response sent');
  }
});

app.post('/api/protected/items', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const { title, content }: CreateItemRequest = req.body;
    const item = {
      id: uuidv4(),
      userId: req.user?.sub,
      title,
      content,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const params = {
      TableName: process.env.DYNAMODB_TABLE_NAME || 'gamani-items',
      Item: item
    };

    const putCommand = new PutCommand(params);
    await dynamodb.send(putCommand);
    res.json(createApiResponse({ item }, 'Item created successfully'));
  } catch (error) {
    log('❌ [ITEMS API]', 'DynamoDB error (create):', error);
    res.status(500).json(createErrorResponse('Failed to create item'));
  }
});

// Project management routes
app.get('/api/protected/projects', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  log('🔍 [PROJECTS API]', 'GET /api/protected/projects - Starting');
  log('🔍 [PROJECTS API]', 'User sub:', req.user?.sub);
  
  try {
    const params = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': req.user?.sub
      }
    };

    log('🔍 [PROJECTS API]', 'DynamoDB params:', JSON.stringify(params, null, 2));
    
    const command = new ScanCommand(params);
    const result = await dynamodb.send(command);
    
    log('✅ [PROJECTS API]', 'DynamoDB scan completed successfully');
    log('✅ [PROJECTS API]', 'Result:', JSON.stringify(result, null, 2));
    
    res.json(createApiResponse({ projects: result.Items }, 'Projects retrieved successfully'));
  } catch (error) {
    log('❌ [PROJECTS API]', 'DynamoDB error:', error);
    res.status(500).json(createErrorResponse('Failed to fetch projects'));
  }
});

app.post('/api/protected/projects', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  log('📝 [PROJECTS API]', 'POST /api/protected/projects - Starting');
  
  try {
    const { name, description }: CreateProjectRequest = req.body;
    
    if (!name || !name.trim()) {
      res.status(400).json(createErrorResponse('Project name is required'));
      return;
    }

    const project = {
      id: uuidv4(),
      userId: req.user?.sub,
      name: name.trim(),
      description: description?.trim() || '',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const params = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      Item: project
    };

    log('📝 [PROJECTS API]', 'Creating project:', JSON.stringify(project, null, 2));
    
    const putCommand = new PutCommand(params);
    await dynamodb.send(putCommand);
    
    log('✅ [PROJECTS API]', 'Project created successfully');
    res.json(createApiResponse({ project }, 'Project created successfully'));
  } catch (error) {
    log('❌ [PROJECTS API]', 'Error creating project:', error);
    res.status(500).json(createErrorResponse('Failed to create project'));
  }
});

app.put('/api/protected/projects/:id', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  log('📝 [PROJECTS API]', 'PUT /api/protected/projects/:id - Starting');
  
  try {
    const { id } = req.params;
    const { name, description }: UpdateProjectRequest = req.body;
    
    if (!id) {
      res.status(400).json(createErrorResponse('Project ID is required'));
      return;
    }

    // First check if project exists and belongs to user
    const getParams = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      Key: { id }
    };

    const getCommand = new GetCommand(getParams);
    const existingProject = await dynamodb.send(getCommand);
    
    if (!existingProject.Item) {
      res.status(404).json(createErrorResponse('Project not found'));
      return;
    }

    if (existingProject.Item.userId !== req.user?.sub) {
      res.status(403).json(createErrorResponse('Not authorized to update this project'));
      return;
    }

    const updateExpression = [];
    const expressionAttributeValues: any = {};
    const expressionAttributeNames: any = {};

    if (name !== undefined) {
      updateExpression.push('#name = :name');
      expressionAttributeNames['#name'] = 'name';
      expressionAttributeValues[':name'] = name.trim();
    }

    if (description !== undefined) {
      updateExpression.push('description = :description');
      expressionAttributeValues[':description'] = description.trim();
    }

    updateExpression.push('updatedAt = :updatedAt');
    expressionAttributeValues[':updatedAt'] = new Date().toISOString();

    const updateParams = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      Key: { id },
      UpdateExpression: `SET ${updateExpression.join(', ')}`,
      ExpressionAttributeValues: expressionAttributeValues,
      ...(Object.keys(expressionAttributeNames).length > 0 && { ExpressionAttributeNames: expressionAttributeNames }),
      ReturnValues: 'ALL_NEW' as const
    };

    log('📝 [PROJECTS API]', 'Updating project:', JSON.stringify(updateParams, null, 2));
    
    const updateCommand = new UpdateCommand(updateParams);
    const result = await dynamodb.send(updateCommand);
    
    log('✅ [PROJECTS API]', 'Project updated successfully');
    res.json(createApiResponse({ project: result.Attributes }, 'Project updated successfully'));
  } catch (error) {
    log('❌ [PROJECTS API]', 'Error updating project:', error);
    res.status(500).json(createErrorResponse('Failed to update project'));
  }
});

app.delete('/api/protected/projects/:id', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  log('🗑️ [PROJECTS API]', 'DELETE /api/protected/projects/:id - Starting');
  
  try {
    const { id } = req.params;
    
    if (!id) {
      res.status(400).json(createErrorResponse('Project ID is required'));
      return;
    }

    // First check if project exists and belongs to user
    const getParams = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      Key: { id }
    };

    const getCommand = new GetCommand(getParams);
    const existingProject = await dynamodb.send(getCommand);
    
    if (!existingProject.Item) {
      res.status(404).json(createErrorResponse('Project not found'));
      return;
    }

    if (existingProject.Item.userId !== req.user?.sub) {
      res.status(403).json(createErrorResponse('Not authorized to delete this project'));
      return;
    }

    const deleteParams = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      Key: { id }
    };

    log('🗑️ [PROJECTS API]', 'Deleting project:', id);
    
    const deleteCommand = new DeleteCommand(deleteParams);
    await dynamodb.send(deleteCommand);
    
    log('✅ [PROJECTS API]', 'Project deleted successfully');
    res.json(createApiResponse({}, 'Project deleted successfully'));
  } catch (error) {
    log('❌ [PROJECTS API]', 'Error deleting project:', error);
    res.status(500).json(createErrorResponse('Failed to delete project'));
  }
});

// Chat history routes
app.get('/api/protected/projects/:id/messages', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  log('💬 [CHAT API]', 'GET /api/protected/projects/:id/messages - Starting');
  
  try {
    const { id: projectId } = req.params;
    
    if (!projectId) {
      res.status(400).json(createErrorResponse('Project ID is required'));
      return;
    }

    // First verify the project belongs to the user
    const projectParams = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      Key: { id: projectId }
    };

    const projectGetCommand = new GetCommand(projectParams);
    const projectResult = await dynamodb.send(projectGetCommand);
    
    if (!projectResult.Item) {
      res.status(404).json(createErrorResponse('Project not found'));
      return;
    }

    if (projectResult.Item.userId !== req.user?.sub) {
      res.status(403).json(createErrorResponse('Not authorized to access this project'));
      return;
    }

    // Get chat messages for the project
    const params = {
      TableName: process.env.DYNAMODB_MESSAGES_TABLE || 'gamani-messages',
      FilterExpression: 'projectId = :projectId',
      ExpressionAttributeValues: {
        ':projectId': projectId
      }
    };

    log('💬 [CHAT API]', 'Fetching messages for project:', projectId);
    
    const command = new ScanCommand(params);
    const result = await dynamodb.send(command);
    
    // Sort messages by timestamp
    const messages = (result.Items || []).sort((a, b) => 
      new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
    );
    
    log('✅ [CHAT API]', 'Messages retrieved successfully, count:', messages.length);
    res.json(createApiResponse({ messages }, 'Messages retrieved successfully'));
  } catch (error) {
    log('❌ [CHAT API]', 'Error fetching messages:', error);
    res.status(500).json(createErrorResponse('Failed to fetch messages'));
  }
});

app.post('/api/protected/projects/:id/messages', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  log('💬 [CHAT API]', 'POST /api/protected/projects/:id/messages - Starting');
  
  try {
    const { id: projectId } = req.params;
    const { role, content, gameCode }: CreateMessageRequest = req.body;
    
    if (!projectId) {
      res.status(400).json(createErrorResponse('Project ID is required'));
      return;
    }

    if (!role || !content) {
      res.status(400).json(createErrorResponse('Role and content are required'));
      return;
    }

    if (!['user', 'assistant'].includes(role)) {
      res.status(400).json(createErrorResponse('Role must be either "user" or "assistant"'));
      return;
    }

    // First verify the project belongs to the user
    const projectParams = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      Key: { id: projectId }
    };

    const projectGetCommand = new GetCommand(projectParams);
    const projectResult = await dynamodb.send(projectGetCommand);
    
    if (!projectResult.Item) {
      res.status(404).json(createErrorResponse('Project not found'));
      return;
    }

    if (projectResult.Item.userId !== req.user?.sub) {
      res.status(403).json(createErrorResponse('Not authorized to access this project'));
      return;
    }

    // Create the message
    const message = {
      id: uuidv4(),
      projectId,
      role,
      content,
      ...(gameCode && { gameCode }),
      timestamp: new Date().toISOString()
    };

    const params = {
      TableName: process.env.DYNAMODB_MESSAGES_TABLE || 'gamani-messages',
      Item: message
    };

    log('💬 [CHAT API]', 'Saving message:', JSON.stringify(message, null, 2));
    
    const putCommand = new PutCommand(params);
    await dynamodb.send(putCommand);
    
    log('✅ [CHAT API]', 'Message saved successfully');
    res.json(createApiResponse({ message }, 'Message saved successfully'));
  } catch (error) {
    log('❌ [CHAT API]', 'Error saving message:', error);
    res.status(500).json(createErrorResponse('Failed to save message'));
  }
});

app.delete('/api/protected/projects/:id/messages', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  log('💬 [CHAT API]', 'DELETE /api/protected/projects/:id/messages - Starting');
  
  try {
    const { id: projectId } = req.params;
    
    if (!projectId) {
      res.status(400).json(createErrorResponse('Project ID is required'));
      return;
    }

    // First verify the project belongs to the user
    const projectParams = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      Key: { id: projectId }
    };

    const projectGetCommand = new GetCommand(projectParams);
    const projectResult = await dynamodb.send(projectGetCommand);
    
    if (!projectResult.Item) {
      res.status(404).json(createErrorResponse('Project not found'));
      return;
    }

    if (projectResult.Item.userId !== req.user?.sub) {
      res.status(403).json(createErrorResponse('Not authorized to access this project'));
      return;
    }

    // Get all messages for the project first
    const scanParams = {
      TableName: process.env.DYNAMODB_MESSAGES_TABLE || 'gamani-messages',
      FilterExpression: 'projectId = :projectId',
      ExpressionAttributeValues: {
        ':projectId': projectId
      }
    };

    const scanCommand = new ScanCommand(scanParams);
    const scanResult = await dynamodb.send(scanCommand);
    const messages = scanResult.Items || [];

    log('💬 [CHAT API]', 'Found', messages.length, 'messages to delete for project:', projectId);

    // Delete each message individually (DynamoDB doesn't support batch delete with filter)
    const deletePromises = messages.map(message => {
      const deleteParams = {
        TableName: process.env.DYNAMODB_MESSAGES_TABLE || 'gamani-messages',
        Key: { id: message.id }
      };
      const deleteCommand = new DeleteCommand(deleteParams);
      return dynamodb.send(deleteCommand);
    });

    await Promise.all(deletePromises);
    
    log('✅ [CHAT API]', 'All messages deleted successfully');
    res.json(createApiResponse({ deletedCount: messages.length }, 'Messages cleared successfully'));
  } catch (error) {
    log('❌ [CHAT API]', 'Error clearing messages:', error);
    res.status(500).json(createErrorResponse('Failed to clear messages'));
  }
});

// AI routes using Google Generative AI
app.post('/api/protected/ai/generate', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const { prompt, conversation, currentGame }: AIGenerateRequest = req.body;
    
    if (!prompt) {
      res.status(400).json({ error: 'Prompt is required' });
      return;
    }

    if (!genAI) {
      log('❌ [GOOGLE AI]', 'AI service not initialized - this should not happen with fail-fast startup');
      res.status(503).json(createErrorResponse('AI service not available. Server may be starting up.'));
      return;
    }

    // Build conversation context for AI
    let contextualPrompt = '';
    
    // If there's a conversation history, include it for context
    if (conversation && conversation.length > 0) {
      contextualPrompt += 'Previous conversation context:\n';
      conversation.forEach((msg, index) => {
        // Only include the last 10 messages to avoid token limits
        if (index >= conversation.length - 10) {
          contextualPrompt += `${msg.role === 'user' ? 'User' : 'Assistant'}: ${msg.content}\n`;
        }
      });
      contextualPrompt += '\n';
    }

    // If there's a current game, include it for context
    if (currentGame) {
      contextualPrompt += 'Current game code for reference/modification:\n';
      contextualPrompt += `${currentGame}\n\n`;
    }

    // Enhanced prompt for game development with conversation context
    const gamePrompt = `You are a children's game developer assistant. You maintain context across conversations and can modify existing games based on user requests.

${contextualPrompt}Current user request: "${prompt}"

Instructions:
- If this is a modification request and you have previous game code, modify the existing game accordingly
- If this is a new game request, create a complete, fun, interactive game in Hebrew
- Create a complete HTML page with embedded CSS and JavaScript
- The game should be child-friendly and fun
- Use Hebrew text for all UI elements and instructions
- Make it interactive and engaging
- Include clear game instructions in Hebrew
- Use bright colors and appealing visuals
- Ensure the game works on both desktop and mobile
- The HTML should be complete and ready to display in an iframe
- If the user asks about something other than game creation/modification, respond conversationally but try to steer back to game development

If you're creating/modifying a game, return ONLY the complete HTML code, starting with <!DOCTYPE html> and ending with </html>. Do not include any explanations or markdown formatting.

If you're having a conversation, respond naturally in Hebrew or English based on the user's language.`;

    const result = await genAI.models.generateContent({
      model: 'gemini-2.0-flash-exp',
      contents: [{
        role: 'user',
        parts: [{ text: gamePrompt }]
      }]
    });
    
    const text = result.text || '';

    log('✅ [GOOGLE AI]', 'Generated response with conversation context:', {
      promptLength: prompt.length,
      conversationLength: conversation?.length || 0,
      hasCurrentGame: !!currentGame,
      responseLength: text.length
    });

    res.json(createApiResponse({ response: text }, 'AI response generated successfully'));
  } catch (error) {
    log('❌ [GOOGLE AI]', 'Google AI error:', error);
    res.status(500).json(createErrorResponse('Failed to generate AI response'));
  }
});

// Game Sharing API Endpoints

// Share a game (protected endpoint)
app.post('/api/protected/games/share', authenticateCognito, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { title, content, description } = req.body;
    const userId = req.user?.sub;

    if (!title || !content) {
      res.status(400).json(createErrorResponse('Title and content are required'));
      return;
    }

    // Generate a unique share ID
    const shareId = uuidv4();
    const now = new Date().toISOString();

    const sharedGame = {
      shareId,
      userId,
      title,
      content, // HTML game content
      description: description || '',
      createdAt: now,
      accessCount: 0
    };

    // Save to DynamoDB
    const shareGameCommand = new PutCommand({
      TableName: 'gamani-shared-games',
      Item: sharedGame
    });
    await dynamodb.send(shareGameCommand);

    res.json(createApiResponse({ 
      shareId,
      shareUrl: `${req.protocol}://${req.get('host')}/shared/${shareId}`
    }, 'Game shared successfully'));
  } catch (error) {
    log('❌ [SHARING]', 'Share game error:', error);
    res.status(500).json(createErrorResponse('Failed to share game'));
  }
});

// Get shared game (public endpoint - no authentication required)
app.get('/api/games/:shareId', async (req: Request, res: Response) => {
  try {
    const { shareId } = req.params;

    const getSharedGameCommand = new GetCommand({
      TableName: 'gamani-shared-games',
      Key: { shareId }
    });
    const result = await dynamodb.send(getSharedGameCommand);

    if (!result.Item) {
      res.status(404).json(createErrorResponse('Shared game not found'));
      return;
    }

    // Increment access count
    const incrementCommand = new UpdateCommand({
      TableName: 'gamani-shared-games',
      Key: { shareId },
      UpdateExpression: 'SET accessCount = accessCount + :inc',
      ExpressionAttributeValues: {
        ':inc': 1
      }
    });
    await dynamodb.send(incrementCommand);

    // Return game data without sensitive information
    const gameData = {
      shareId: result.Item.shareId,
      title: result.Item.title,
      content: result.Item.content,
      description: result.Item.description,
      createdAt: result.Item.createdAt,
      accessCount: (result.Item.accessCount || 0) + 1
    };

    res.json(createApiResponse(gameData, 'Shared game retrieved successfully'));
  } catch (error) {
    log('❌ [SHARING]', 'Get shared game error:', error);
    res.status(500).json(createErrorResponse('Failed to retrieve shared game'));
  }
});

// Get user's shared games (protected endpoint)
app.get('/api/protected/games/shared', authenticateCognito, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const userId = req.user?.sub;

    const scanSharedGamesCommand = new ScanCommand({
      TableName: 'gamani-shared-games',
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': userId
      }
    });
    const result = await dynamodb.send(scanSharedGamesCommand);

    const sharedGames = result.Items?.map(item => ({
      shareId: item.shareId,
      title: item.title,
      description: item.description,
      createdAt: item.createdAt,
      accessCount: item.accessCount || 0
    })) || [];

    res.json(createApiResponse(sharedGames, 'Shared games retrieved successfully'));
  } catch (error) {
    log('❌ [SHARING]', 'Get shared games error:', error);
    res.status(500).json(createErrorResponse('Failed to retrieve shared games'));
  }
});

// Delete shared game (protected endpoint)
app.delete('/api/protected/games/:shareId', authenticateCognito, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { shareId } = req.params;
    const userId = req.user?.sub;

    // First check if the game exists and belongs to the user
    const getSharedGameCommand = new GetCommand({
      TableName: 'gamani-shared-games',
      Key: { shareId }
    });
    const result = await dynamodb.send(getSharedGameCommand);

    if (!result.Item) {
      res.status(404).json(createErrorResponse('Shared game not found'));
      return;
    }

    if (result.Item.userId !== userId) {
      res.status(403).json(createErrorResponse('Not authorized to delete this shared game'));
      return;
    }

    // Delete the shared game
    const deleteSharedGameCommand = new DeleteCommand({
      TableName: 'gamani-shared-games',
      Key: { shareId }
    });
    await dynamodb.send(deleteSharedGameCommand);

    res.json(createApiResponse({}, 'Shared game deleted successfully'));
  } catch (error) {
    log('❌ [SHARING]', 'Delete shared game error:', error);
    res.status(500).json(createErrorResponse('Failed to delete shared game'));
  }
});

// Catch-all handler for React Router
app.get('*', (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', '..', '..', '..', 'client', 'dist', 'index.html'));
});

// Error handling middleware
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  log('❌ [ERROR]', 'Unhandled error:', err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start server only after all critical services are initialized
async function startServer(): Promise<void> {
  try {
    // Initialize all critical services first
    await initializeCriticalServices();
    
    // Only start the HTTP server if all services initialized successfully
    app.listen(PORT, () => {
      // Get version info from environment or package.json
      const version = process.env.APP_VERSION || '1.0.0';
      const gitCommit = process.env.APP_GIT_COMMIT || 'unknown';
      const buildTime = process.env.APP_BUILD_TIME || 'unknown';
      const deployedBy = process.env.APP_DEPLOYED_BY || 'unknown';
      
      log('🚀 [SERVER]', `Gamani app v${version} listening on port ${PORT}`);
      log('🚀 [SERVER]', `Environment: ${process.env.NODE_ENV || 'development'}`);
      log('📦 [VERSION]', `Git commit: ${gitCommit}`);
      log('📦 [VERSION]', `Build time: ${buildTime}`);
      log('📦 [VERSION]', `Deployed by: ${deployedBy}`);
      log('🚀 [SERVER]', `All services initialized successfully`);
    });
  } catch (error) {
    log('💥 [SERVER]', 'Failed to start server due to initialization errors');
    process.exit(1);
  }
}

// Start the server
startServer();