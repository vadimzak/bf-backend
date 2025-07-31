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
}

const app = express();
const PORT = process.env.PORT || 3002;

// AWS SDK v3 Configuration
const awsRegion = process.env.AWS_REGION || 'il-central-1';

// AWS SDK v3 automatically picks up IRSA credentials when environment variables are present
console.log('🔧 [AWS] Initializing AWS SDK v3 clients');
console.log('🔧 [AWS] Region:', awsRegion);

if (process.env.NODE_ENV !== 'production') {
  console.log('🔧 [AWS] Development mode - using environment credentials');
} else {
  console.log('🔧 [AWS] Production mode - using IRSA credentials');
  if (process.env.AWS_ROLE_ARN && process.env.AWS_WEB_IDENTITY_TOKEN_FILE) {
    console.log('✅ [AWS] IRSA environment variables detected');
    console.log('🔧 [AWS] Role ARN:', process.env.AWS_ROLE_ARN);
  }
}

// Initialize AWS SDK v3 clients
const dynamoClient = new DynamoDBClient({ region: awsRegion });
const secretsManagerClient = new SecretsManagerClient({ region: awsRegion });

console.log('✅ [AWS] SDK v3 clients initialized');

// Initialize Cognito JWT Verifier
const jwtVerifier = CognitoJwtVerifier.create({
  userPoolId: 'il-central-1_aJg6S7Rl3',
  tokenUse: 'access',
  clientId: '1qa3m3ok5i8ehg0ef8jg3fnff6',
});

console.log('✅ Cognito JWT Verifier initialized');

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
async function initializeGoogleAI() {
  try {
    console.log('🔐 [GOOGLE AI] Fetching API key from Secrets Manager...');
    const command = new GetSecretValueCommand({
      SecretId: 'gamani/google-ai-api-key'
    });
    const result = await secretsManagerClient.send(command);
    
    const apiKey = result.SecretString;
    if (!apiKey || apiKey === 'PLACEHOLDER_KEY_NEEDS_UPDATE') {
      console.warn('⚠️ [GOOGLE AI] API key is placeholder or missing. Game generation will not work.');
      return;
    }
    
    genAI = new GoogleGenAI({
      apiKey: apiKey
    });
    console.log('✅ [GOOGLE AI] Initialized successfully');
  } catch (error) {
    console.error('❌ [GOOGLE AI] Failed to fetch API key from Secrets Manager:', error);
    console.warn('⚠️ [GOOGLE AI] Game generation will not work without API key');
  }
}

// Initialize Google AI on startup
initializeGoogleAI();

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
  const timestamp = new Date().toISOString();
  console.log(`📡 [SERVER REQUEST] ${timestamp} - ${req.method} ${req.path}`);
  if (req.headers.authorization) {
    console.log(`📡 [SERVER REQUEST] Has authorization header: ${req.headers.authorization.substring(0, 20)}...`);
  }
  next();
});

// Cognito Auth middleware
const authenticateCognito = async (req: AuthenticatedRequest, res: Response, next: NextFunction): Promise<void> => {
  const timestamp = new Date().toISOString();
  console.log(`🔐 [SERVER AUTH] ${timestamp} - Cognito authentication attempt for ${req.method} ${req.path}`);
  
  try {
    const authHeader = req.headers.authorization;
    console.log('🔐 [SERVER AUTH] Authorization header present:', !!authHeader);
    console.log('🔐 [SERVER AUTH] Authorization header starts with Bearer:', authHeader?.startsWith('Bearer ') || false);
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      console.log('❌ [SERVER AUTH] No valid authorization header');
      res.status(401).json({ error: 'No valid authorization header' });
      return;
    }

    const accessToken = authHeader.split('Bearer ')[1];
    console.log('🔐 [SERVER AUTH] Access Token length:', accessToken.length);
    console.log('🔐 [SERVER AUTH] Access Token preview:', accessToken.substring(0, 20) + '...');
    
    console.log('🔐 [SERVER AUTH] Verifying token with Cognito...');
    const payload = await jwtVerifier.verify(accessToken);
    console.log('✅ [SERVER AUTH] Token verification successful');
    console.log('✅ [SERVER AUTH] User details:', { 
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
    console.error('❌ [SERVER AUTH] Cognito auth error:', error);
    console.error('❌ [SERVER AUTH] Error details:', {
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
  const appInfo = getAppInfo('gamani', '1.0.0');
  const healthData = {
    ...appInfo,
    status: 'healthy',
    uptimeFormatted: formatUptime(appInfo.uptime),
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
  console.log('✅ [SERVER AUTH] /api/auth/verify - User authenticated successfully');
  const userData = {
    sub: req.user?.sub,
    username: req.user?.username,
    email: req.user?.email,
    email_verified: req.user?.email_verified
  };
  console.log('✅ [SERVER AUTH] Returning user data:', userData);
  res.json(createApiResponse(userData, 'User authenticated successfully'));
});

// Protected API routes
app.use('/api/protected', authenticateCognito);

// DynamoDB routes
app.get('/api/protected/items', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  console.log('🔍 [ITEMS API] GET /api/protected/items - Starting');
  console.log('🔍 [ITEMS API] User sub:', req.user?.sub);
  console.log('🔍 [ITEMS API] Table name:', process.env.DYNAMODB_TABLE_NAME || 'gamani-items');
  
  try {
    const params = {
      TableName: process.env.DYNAMODB_TABLE_NAME || 'gamani-items',
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': req.user?.sub
      }
    };

    console.log('🔍 [ITEMS API] DynamoDB params:', JSON.stringify(params, null, 2));
    console.log('🔍 [ITEMS API] About to call dynamodb.scan()...');
    
    const command = new ScanCommand(params);
    const result = await dynamodb.send(command);
    
    console.log('✅ [ITEMS API] DynamoDB scan completed successfully');
    console.log('✅ [ITEMS API] Result:', JSON.stringify(result, null, 2));
    
    res.json(createApiResponse({ items: result.Items }, 'Items retrieved successfully'));
    console.log('✅ [ITEMS API] Response sent successfully');
  } catch (error) {
    console.error('❌ [ITEMS API] DynamoDB error:', error);
    res.status(500).json(createErrorResponse('Failed to fetch items'));
    console.log('❌ [ITEMS API] Error response sent');
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
    console.error('DynamoDB error:', error);
    res.status(500).json(createErrorResponse('Failed to create item'));
  }
});

// Project management routes
app.get('/api/protected/projects', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  console.log('🔍 [PROJECTS API] GET /api/protected/projects - Starting');
  console.log('🔍 [PROJECTS API] User sub:', req.user?.sub);
  
  try {
    const params = {
      TableName: process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects',
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': req.user?.sub
      }
    };

    console.log('🔍 [PROJECTS API] DynamoDB params:', JSON.stringify(params, null, 2));
    
    const command = new ScanCommand(params);
    const result = await dynamodb.send(command);
    
    console.log('✅ [PROJECTS API] DynamoDB scan completed successfully');
    console.log('✅ [PROJECTS API] Result:', JSON.stringify(result, null, 2));
    
    res.json(createApiResponse({ projects: result.Items }, 'Projects retrieved successfully'));
  } catch (error) {
    console.error('❌ [PROJECTS API] DynamoDB error:', error);
    res.status(500).json(createErrorResponse('Failed to fetch projects'));
  }
});

app.post('/api/protected/projects', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  console.log('📝 [PROJECTS API] POST /api/protected/projects - Starting');
  
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

    console.log('📝 [PROJECTS API] Creating project:', JSON.stringify(project, null, 2));
    
    const putCommand = new PutCommand(params);
    await dynamodb.send(putCommand);
    
    console.log('✅ [PROJECTS API] Project created successfully');
    res.json(createApiResponse({ project }, 'Project created successfully'));
  } catch (error) {
    console.error('❌ [PROJECTS API] Error creating project:', error);
    res.status(500).json(createErrorResponse('Failed to create project'));
  }
});

app.put('/api/protected/projects/:id', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  console.log('📝 [PROJECTS API] PUT /api/protected/projects/:id - Starting');
  
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

    console.log('📝 [PROJECTS API] Updating project:', JSON.stringify(updateParams, null, 2));
    
    const updateCommand = new UpdateCommand(updateParams);
    const result = await dynamodb.send(updateCommand);
    
    console.log('✅ [PROJECTS API] Project updated successfully');
    res.json(createApiResponse({ project: result.Attributes }, 'Project updated successfully'));
  } catch (error) {
    console.error('❌ [PROJECTS API] Error updating project:', error);
    res.status(500).json(createErrorResponse('Failed to update project'));
  }
});

app.delete('/api/protected/projects/:id', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  console.log('🗑️ [PROJECTS API] DELETE /api/protected/projects/:id - Starting');
  
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

    console.log('🗑️ [PROJECTS API] Deleting project:', id);
    
    const deleteCommand = new DeleteCommand(deleteParams);
    await dynamodb.send(deleteCommand);
    
    console.log('✅ [PROJECTS API] Project deleted successfully');
    res.json(createApiResponse({}, 'Project deleted successfully'));
  } catch (error) {
    console.error('❌ [PROJECTS API] Error deleting project:', error);
    res.status(500).json(createErrorResponse('Failed to delete project'));
  }
});

// Chat history routes
app.get('/api/protected/projects/:id/messages', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  console.log('💬 [CHAT API] GET /api/protected/projects/:id/messages - Starting');
  
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

    console.log('💬 [CHAT API] Fetching messages for project:', projectId);
    
    const command = new ScanCommand(params);
    const result = await dynamodb.send(command);
    
    // Sort messages by timestamp
    const messages = (result.Items || []).sort((a, b) => 
      new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
    );
    
    console.log('✅ [CHAT API] Messages retrieved successfully, count:', messages.length);
    res.json(createApiResponse({ messages }, 'Messages retrieved successfully'));
  } catch (error) {
    console.error('❌ [CHAT API] Error fetching messages:', error);
    res.status(500).json(createErrorResponse('Failed to fetch messages'));
  }
});

app.post('/api/protected/projects/:id/messages', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  console.log('💬 [CHAT API] POST /api/protected/projects/:id/messages - Starting');
  
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

    console.log('💬 [CHAT API] Saving message:', JSON.stringify(message, null, 2));
    
    const putCommand = new PutCommand(params);
    await dynamodb.send(putCommand);
    
    console.log('✅ [CHAT API] Message saved successfully');
    res.json(createApiResponse({ message }, 'Message saved successfully'));
  } catch (error) {
    console.error('❌ [CHAT API] Error saving message:', error);
    res.status(500).json(createErrorResponse('Failed to save message'));
  }
});

app.delete('/api/protected/projects/:id/messages', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  console.log('💬 [CHAT API] DELETE /api/protected/projects/:id/messages - Starting');
  
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

    console.log('💬 [CHAT API] Found', messages.length, 'messages to delete for project:', projectId);

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
    
    console.log('✅ [CHAT API] All messages deleted successfully');
    res.json(createApiResponse({ deletedCount: messages.length }, 'Messages cleared successfully'));
  } catch (error) {
    console.error('❌ [CHAT API] Error clearing messages:', error);
    res.status(500).json(createErrorResponse('Failed to clear messages'));
  }
});

// AI routes using Google Generative AI
app.post('/api/protected/ai/generate', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const { prompt }: AIGenerateRequest = req.body;
    
    if (!prompt) {
      res.status(400).json({ error: 'Prompt is required' });
      return;
    }

    if (!genAI) {
      console.error('❌ [GOOGLE AI] AI service not initialized');
      res.status(503).json(createErrorResponse('AI service not available. Please check server configuration.'));
      return;
    }

    // Enhanced prompt for game development
    const gamePrompt = `You are a children's game developer. Create a complete, fun, interactive game in Hebrew based on this request: "${prompt}"

Instructions:
- Create a complete HTML page with embedded CSS and JavaScript
- The game should be child-friendly and fun
- Use Hebrew text for all UI elements and instructions
- Make it interactive and engaging
- Include clear game instructions in Hebrew
- Use bright colors and appealing visuals
- Ensure the game works on both desktop and mobile
- The HTML should be complete and ready to display in an iframe

Return ONLY the complete HTML code, starting with <!DOCTYPE html> and ending with </html>. Do not include any explanations or markdown formatting.`;

    const result = await genAI.models.generateContent({
      model: 'gemini-2.0-flash-exp',
      contents: [{
        role: 'user',
        parts: [{ text: gamePrompt }]
      }]
    });
    
    const text = result.text;

    res.json(createApiResponse({ response: text }, 'AI response generated successfully'));
  } catch (error) {
    console.error('Google AI error:', error);
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
    console.error('Share game error:', error);
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
    console.error('Get shared game error:', error);
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
    console.error('Get shared games error:', error);
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
    console.error('Delete shared game error:', error);
    res.status(500).json(createErrorResponse('Failed to delete shared game'));
  }
});

// Catch-all handler for React Router
app.get('*', (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', '..', '..', '..', 'client', 'dist', 'index.html'));
});

// Error handling middleware
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Start server
app.listen(PORT, () => {
  console.log(`Gamani app listening on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`Cognito JWT Verifier initialized: Yes`);
});