import { Response } from 'express';
import { createApiResponse, createErrorResponse } from '@bf-backend/server-core';
import { AuthenticatedRequest, CreateMessageRequest } from '../types';
import { MessageService } from '../services';
import { validateRequired, validateId, validateRole } from '../utils/validation';

export class MessageController {
  static async getMessages(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { id: projectId } = req.params;
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      if (!validateId(projectId, res, 'Project ID')) {
        return;
      }

      const messages = await MessageService.getMessages(userId, projectId);
      res.json(createApiResponse({ messages }, 'Messages retrieved successfully'));
    } catch (error: any) {
      if (error.message === 'Project not found') {
        res.status(404).json(createErrorResponse('Project not found'));
      } else if (error.message === 'Not authorized to access this project') {
        res.status(403).json(createErrorResponse('Not authorized to access this project'));
      } else {
        res.status(500).json(createErrorResponse('Failed to fetch messages'));
      }
    }
  }

  static async createMessage(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { id: projectId } = req.params;
      const { role, content, gameCode }: CreateMessageRequest = req.body;
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      if (!validateId(projectId, res, 'Project ID')) {
        return;
      }

      if (!validateRequired({ role, content }, res)) {
        return;
      }

      if (!validateRole(role, res)) {
        return;
      }

      const message = await MessageService.createMessage(userId, projectId, { role, content, gameCode });
      res.json(createApiResponse({ message }, 'Message saved successfully'));
    } catch (error: any) {
      if (error.message === 'Project not found') {
        res.status(404).json(createErrorResponse('Project not found'));
      } else if (error.message === 'Not authorized to access this project') {
        res.status(403).json(createErrorResponse('Not authorized to access this project'));
      } else {
        res.status(500).json(createErrorResponse('Failed to save message'));
      }
    }
  }

  static async clearMessages(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { id: projectId } = req.params;
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      if (!validateId(projectId, res, 'Project ID')) {
        return;
      }

      const deletedCount = await MessageService.clearMessages(userId, projectId);
      res.json(createApiResponse({ deletedCount }, 'Messages cleared successfully'));
    } catch (error: any) {
      if (error.message === 'Project not found') {
        res.status(404).json(createErrorResponse('Project not found'));
      } else if (error.message === 'Not authorized to access this project') {
        res.status(403).json(createErrorResponse('Not authorized to access this project'));
      } else {
        res.status(500).json(createErrorResponse('Failed to clear messages'));
      }
    }
  }
}