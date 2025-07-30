import express, { Request, Response, NextFunction } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import { serverCore, getAppInfo, formatUptime, createApiResponse, createErrorResponse, AppInfo } from '@bf-backend/server-core';
import dotenv from 'dotenv';

// Firebase Admin SDK
import * as admin from 'firebase-admin';

// AWS SDK for DynamoDB and Secrets Manager
import AWS from 'aws-sdk';

// Google Generative AI
import { GoogleGenerativeAI } from '@google/generative-ai';

dotenv.config();

// Types
interface AuthenticatedRequest extends Request {
  user?: admin.auth.DecodedIdToken;
}

interface CreateItemRequest {
  title: string;
  content: string;
}

interface AIGenerateRequest {
  prompt: string;
}

const app = express();
const PORT = process.env.PORT || 3002;

// AWS Secrets Manager
AWS.config.credentials = new AWS.SharedIniFileCredentials({ profile: 'bf' });
const secretsManager = new AWS.SecretsManager({
  region: process.env.AWS_REGION || 'il-central-1'
});

// Function to get Firebase service account from AWS Secrets Manager
async function getFirebaseCredentials(): Promise<any> {
  const secretName = 'gamani/firebase/service-account';
  
  try {
    console.log('Fetching Firebase credentials from AWS Secrets Manager...');
    const result = await secretsManager.getSecretValue({ SecretId: secretName }).promise();
    
    if (result.SecretString) {
      return JSON.parse(result.SecretString);
    } else {
      throw new Error('Secret string is empty');
    }
  } catch (error) {
    console.error('Failed to fetch Firebase credentials from Secrets Manager:', error);
    return null;
  }
}

// Initialize Firebase Admin asynchronously
async function initializeFirebaseAdmin(): Promise<void> {
  if (admin.apps.length > 0) {
    console.log('Firebase Admin already initialized');
    return;
  }

  try {
    // First try AWS Secrets Manager (production)
    const serviceAccount = await getFirebaseCredentials();
    if (serviceAccount) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      console.log('✅ Firebase Admin initialized from AWS Secrets Manager');
      return;
    }

    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      const serviceAccountFromEnv = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccountFromEnv),
      });
      console.log('✅ Firebase Admin initialized from environment variable');
      return;
    }

    // No credentials found
    console.warn('⚠️ No Firebase credentials found. Authentication will not work.');
    console.warn('Options:');
    console.warn('1. Store credentials in AWS Secrets Manager (production)');
    console.warn('2. Set GOOGLE_APPLICATION_CREDENTIALS environment variable');
    console.warn('3. Set FIREBASE_SERVICE_ACCOUNT_JSON environment variable');
    
  } catch (error) {
    console.error('❌ Failed to initialize Firebase Admin:', error);
  }
}

// Initialize AWS DynamoDB
const dynamodb = new AWS.DynamoDB.DocumentClient({
  region: process.env.AWS_REGION || 'il-central-1'
});

// Initialize Google Generative AI
const genAI = new GoogleGenerativeAI(process.env.GOOGLE_AI_API_KEY || '');

// Middleware - Configure CSP to allow Firebase auth
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: [
        "'self'",
        "'unsafe-inline'", // Needed for Firebase auth popup
        "https://apis.google.com",
        "https://www.gstatic.com",
        "https://accounts.google.com",
        "https://*.firebaseapp.com",
        "https://www.googleapis.com"
      ],
      styleSrc: [
        "'self'",
        "'unsafe-inline'", // Needed for dynamic styles
        "https://accounts.google.com",
        "https://fonts.googleapis.com"
      ],
      fontSrc: [
        "'self'",
        "https://fonts.gstatic.com"
      ],
      connectSrc: [
        "'self'",
        "https://identitytoolkit.googleapis.com",
        "https://securetoken.googleapis.com",
        "https://accounts.google.com",
        "https://*.firebaseapp.com",
        "https://firebase.googleapis.com",
        "https://www.googleapis.com"
      ],
      frameSrc: [
        "'self'",
        "https://accounts.google.com",
        "https://*.firebaseapp.com"
      ],
      imgSrc: [
        "'self'",
        "data:",
        "https:",
        "https://www.gstatic.com",
        "https://lh3.googleusercontent.com" // Google profile images
      ]
    }
  }
}));

app.use(cors({
  origin: process.env.NODE_ENV === 'production' 
    ? ['https://gamani.vadimzak.com'] 
    : ['http://localhost:5173', 'http://localhost:3000', 'http://localhost:3002'],
  credentials: true
}));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(express.static(path.join(__dirname, '..', 'client', 'dist')));

// Request logging middleware
app.use((req: Request, res: Response, next: NextFunction) => {
  const timestamp = new Date().toISOString();
  console.log(`📡 [SERVER REQUEST] ${timestamp} - ${req.method} ${req.path}`);
  if (req.headers.authorization) {
    console.log(`📡 [SERVER REQUEST] Has authorization header: ${req.headers.authorization.substring(0, 20)}...`);
  }
  next();
});

// Firebase Auth middleware
const authenticateFirebase = async (req: AuthenticatedRequest, res: Response, next: NextFunction): Promise<void> => {
  const timestamp = new Date().toISOString();
  console.log(`🔐 [SERVER AUTH] ${timestamp} - Authentication attempt for ${req.method} ${req.path}`);
  
  try {
    // Check if Firebase Admin is initialized
    if (admin.apps.length === 0) {
      console.warn('🔐 [SERVER AUTH] Firebase Admin not initialized, authentication disabled');
      res.status(503).json({ error: 'Authentication service unavailable' });
      return;
    }

    const authHeader = req.headers.authorization;
    console.log('🔐 [SERVER AUTH] Authorization header present:', !!authHeader);
    console.log('🔐 [SERVER AUTH] Authorization header starts with Bearer:', authHeader?.startsWith('Bearer ') || false);
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      console.log('❌ [SERVER AUTH] No valid authorization header');
      res.status(401).json({ error: 'No valid authorization header' });
      return;
    }

    const idToken = authHeader.split('Bearer ')[1];
    console.log('🔐 [SERVER AUTH] ID Token length:', idToken.length);
    console.log('🔐 [SERVER AUTH] ID Token preview:', idToken.substring(0, 20) + '...');
    
    console.log('🔐 [SERVER AUTH] Verifying token with Firebase Admin...');
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    console.log('✅ [SERVER AUTH] Token verification successful');
    console.log('✅ [SERVER AUTH] User details:', { 
      uid: decodedToken.uid, 
      email: decodedToken.email,
      name: decodedToken.name 
    });
    
    req.user = decodedToken;
    next();
  } catch (error: any) {
    console.error('❌ [SERVER AUTH] Firebase auth error:', error);
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
  res.sendFile(path.join(__dirname, '..', 'client', 'dist', 'index.html'));
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
      firebase: !!admin.apps.length,
      dynamodb: !!dynamodb,
      googleAI: !!genAI
    }
  };
  
  res.json(createApiResponse(healthData, 'Health check successful'));
});

// Auth routes
app.post('/api/auth/verify', authenticateFirebase, (req: AuthenticatedRequest, res: Response) => {
  console.log('✅ [SERVER AUTH] /api/auth/verify - User authenticated successfully');
  const userData = {
    uid: req.user?.uid,
    email: req.user?.email,
    name: req.user?.name
  };
  console.log('✅ [SERVER AUTH] Returning user data:', userData);
  res.json(createApiResponse(userData, 'User authenticated successfully'));
});

// Protected API routes
app.use('/api/protected', authenticateFirebase);

// DynamoDB routes
app.get('/api/protected/items', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const params = {
      TableName: process.env.DYNAMODB_TABLE_NAME || 'gamani-items',
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': req.user?.uid
      }
    };

    const result = await dynamodb.scan(params).promise();
    res.json(createApiResponse({ items: result.Items }, 'Items retrieved successfully'));
  } catch (error) {
    console.error('DynamoDB error:', error);
    res.status(500).json(createErrorResponse('Failed to fetch items'));
  }
});

app.post('/api/protected/items', async (req: AuthenticatedRequest, res: Response): Promise<void> => {
  try {
    const { title, content }: CreateItemRequest = req.body;
    const item = {
      id: uuidv4(),
      userId: req.user?.uid,
      title,
      content,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const params = {
      TableName: process.env.DYNAMODB_TABLE_NAME || 'gamani-items',
      Item: item
    };

    await dynamodb.put(params).promise();
    res.json(createApiResponse({ item }, 'Item created successfully'));
  } catch (error) {
    console.error('DynamoDB error:', error);
    res.status(500).json(createErrorResponse('Failed to create item'));
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

    const model = genAI.getGenerativeModel({ model: 'gemini-pro' });
    const result = await model.generateContent(prompt);
    const response = await result.response;
    const text = response.text();

    res.json(createApiResponse({ response: text }, 'AI response generated successfully'));
  } catch (error) {
    console.error('Google AI error:', error);
    res.status(500).json(createErrorResponse('Failed to generate AI response'));
  }
});

// Catch-all handler for React Router
app.get('*', (req: Request, res: Response) => {
  res.sendFile(path.join(__dirname, '..', 'client', 'dist', 'index.html'));
});

// Error handling middleware
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Something went wrong!' });
});

// Initialize Firebase Admin before starting server
initializeFirebaseAdmin().then(() => {
  // Start server
  app.listen(PORT, () => {
    console.log(`Gamani app listening on port ${PORT}`);
    console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`Firebase Admin initialized: ${admin.apps.length > 0 ? 'Yes' : 'No'}`);
  });
}).catch((error) => {
  console.error('Failed to initialize Firebase Admin:', error);
  // Start server anyway for development
  app.listen(PORT, () => {
    console.log(`Gamani app listening on port ${PORT} (Firebase disabled)`);
    console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
  });
});