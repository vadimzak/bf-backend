import { Response } from 'express';
import { createApiResponse, createErrorResponse } from '@bf-backend/server-core';
import { AuthenticatedRequest, CreateItemRequest } from '../types';
import { ItemService } from '../services';
import { validateRequired } from '../utils/validation';

export class ItemController {
  static async getItems(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      const items = await ItemService.getItems(userId);
      res.json(createApiResponse({ items }, 'Items retrieved successfully'));
    } catch (error) {
      res.status(500).json(createErrorResponse('Failed to fetch items'));
    }
  }

  static async createItem(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { title, content }: CreateItemRequest = req.body;
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      if (!validateRequired({ title, content }, res)) {
        return;
      }

      const item = await ItemService.createItem(userId, { title, content });
      res.json(createApiResponse({ item }, 'Item created successfully'));
    } catch (error) {
      res.status(500).json(createErrorResponse('Failed to create item'));
    }
  }
}