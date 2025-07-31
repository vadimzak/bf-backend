import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import path from 'path';

export const configureSecurityMiddleware = (app: express.Application) => {
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
};