import { Request, Response } from 'express';
import { createApiResponse, createErrorResponse } from '@bf-backend/server-core';
import { AuthenticatedRequest, ShareGameRequest } from '../types';
import { GameSharingService } from '../services';
import { validateRequired, validateId } from '../utils/validation';

export class GameController {
  static async shareGame(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { title, content, description }: ShareGameRequest = req.body;
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      if (!validateRequired({ title, content }, res)) {
        return;
      }

      const host = req.get('host') || 'localhost';
      const result = await GameSharingService.shareGame(userId, { title, content, description }, host);
      
      res.json(createApiResponse(result, 'Game shared successfully'));
    } catch (error) {
      console.error('Share game error:', error);
      res.status(500).json(createErrorResponse(`Failed to share game: ${error instanceof Error ? error.message : 'Unknown error'}`));
    }
  }

  static async getSharedGame(req: Request, res: Response): Promise<void> {
    try {
      const { shareId } = req.params;

      console.log('Getting shared game request:', { shareId, url: req.url, path: req.path });

      if (!shareId) {
        console.log('No shareId provided in request');
        res.status(400).json(createErrorResponse('Share ID is required'));
        return;
      }

      console.log('Fetching shared game from service:', shareId);
      const gameData = await GameSharingService.getSharedGame(shareId);
      console.log('Successfully retrieved shared game:', { shareId, title: gameData.title });
      res.json(createApiResponse(gameData, 'Shared game retrieved successfully'));
    } catch (error: any) {
      console.error('Get shared game error:', error);
      if (error.message === 'Shared game not found') {
        res.status(404).json(createErrorResponse('Shared game not found'));
      } else {
        res.status(500).json(createErrorResponse(`Failed to retrieve shared game: ${error.message}`));
      }
    }
  }

  static async getUserSharedGames(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      const sharedGames = await GameSharingService.getUserSharedGames(userId);
      res.json(createApiResponse(sharedGames, 'Shared games retrieved successfully'));
    } catch (error) {
      res.status(500).json(createErrorResponse('Failed to retrieve shared games'));
    }
  }

  static async deleteSharedGame(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { shareId } = req.params;
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      if (!validateId(shareId, res, 'Share ID')) {
        return;
      }

      await GameSharingService.deleteSharedGame(userId, shareId);
      res.json(createApiResponse({}, 'Shared game deleted successfully'));
    } catch (error: any) {
      if (error.message === 'Shared game not found') {
        res.status(404).json(createErrorResponse('Shared game not found'));
      } else if (error.message === 'Not authorized to delete this shared game') {
        res.status(403).json(createErrorResponse('Not authorized to delete this shared game'));
      } else {
        res.status(500).json(createErrorResponse('Failed to delete shared game'));
      }
    }
  }
}