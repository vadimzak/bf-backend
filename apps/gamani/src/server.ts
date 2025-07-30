import express, { Request, Response, NextFunction } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import path from 'path';
import { v4 as uuidv4 } from 'uuid';
import { serverCore } from '@bf-backend/server-core';
import dotenv from 'dotenv';

// Firebase Admin SDK
import * as admin from 'firebase-admin';

// AWS SDK for DynamoDB
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

// Initialize Firebase Admin (only if not already initialized)
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    // Add your Firebase project configuration here
  });
}

// Initialize AWS DynamoDB
const dynamodb = new AWS.DynamoDB.DocumentClient({
  region: process.env.AWS_REGION || 'il-central-1'
});

// Initialize Google Generative AI
const genAI = new GoogleGenerativeAI(process.env.GOOGLE_AI_API_KEY || '');

// Middleware
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:"],
    },
  },
}));

app.use(cors({
  origin: process.env.NODE_ENV === 'production' 
    ? ['https://gamani.vadimzak.com'] 
    : ['http://localhost:5173', 'http://localhost:3000'],
  credentials: true
}));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));
app.use(express.static(path.join(__dirname, '..', 'client', 'dist')));

// Firebase Auth middleware
const authenticateFirebase = async (req: AuthenticatedRequest, res: Response, next: NextFunction): Promise<void> => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({ error: 'No valid authorization header' });
      return;
    }

    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await admin.auth().verifyIdToken(idToken);
    req.user = decodedToken;
    next();
  } catch (error) {
    console.error('Firebase auth error:', error);
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
  res.json({ 
    status: 'healthy',
    service: 'gamani',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
    serverCore: serverCore(),
    services: {
      firebase: !!admin.apps.length,
      dynamodb: !!dynamodb,
      googleAI: !!genAI
    }
  });
});

// Auth routes
app.post('/api/auth/verify', authenticateFirebase, (req: AuthenticatedRequest, res: Response) => {
  res.json({ 
    success: true, 
    user: {
      uid: req.user?.uid,
      email: req.user?.email,
      name: req.user?.name
    }
  });
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
    res.json({ items: result.Items });
  } catch (error) {
    console.error('DynamoDB error:', error);
    res.status(500).json({ error: 'Failed to fetch items' });
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
    res.json({ success: true, item });
  } catch (error) {
    console.error('DynamoDB error:', error);
    res.status(500).json({ error: 'Failed to create item' });
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

    res.json({ 
      success: true, 
      response: text,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('Google AI error:', error);
    res.status(500).json({ error: 'Failed to generate AI response' });
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

// Start server
app.listen(PORT, () => {
  console.log(`Gamani app listening on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});