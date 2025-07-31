import { Response } from 'express';
import { createApiResponse, createErrorResponse } from '@bf-backend/server-core';
import { AuthenticatedRequest, AIGenerateRequest } from '../types';
import { AIService } from '../services';
import { validateRequired } from '../utils/validation';

export class AIController {
  static async generate(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { prompt, conversation, currentGame }: AIGenerateRequest = req.body;
      
      if (!validateRequired({ prompt }, res)) {
        return;
      }

      const response = await AIService.generateResponse({ prompt, conversation, currentGame });
      res.json(createApiResponse({ response }, 'AI response generated successfully'));
    } catch (error: any) {
      if (error.message?.includes('AI service not available')) {
        res.status(503).json(createErrorResponse('AI service not available. Server may be starting up.'));
      } else {
        res.status(500).json(createErrorResponse('Failed to generate AI response'));
      }
    }
  }
}