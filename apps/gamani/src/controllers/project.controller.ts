import { Response } from 'express';
import { createApiResponse, createErrorResponse } from '@bf-backend/server-core';
import { AuthenticatedRequest, CreateProjectRequest, UpdateProjectRequest } from '../types';
import { ProjectService } from '../services';
import { validateRequired, validateId } from '../utils/validation';

export class ProjectController {
  static async getProjects(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      const projects = await ProjectService.getProjects(userId);
      res.json(createApiResponse({ projects }, 'Projects retrieved successfully'));
    } catch (error) {
      res.status(500).json(createErrorResponse('Failed to fetch projects'));
    }
  }

  static async createProject(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { name, description }: CreateProjectRequest = req.body;
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      if (!validateRequired({ name }, res)) {
        return;
      }

      const project = await ProjectService.createProject(userId, { name, description });
      res.json(createApiResponse({ project }, 'Project created successfully'));
    } catch (error) {
      res.status(500).json(createErrorResponse('Failed to create project'));
    }
  }

  static async updateProject(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const { name, description }: UpdateProjectRequest = req.body;
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      if (!validateId(id, res, 'Project ID')) {
        return;
      }

      const project = await ProjectService.updateProject(userId, id, { name, description });
      res.json(createApiResponse({ project }, 'Project updated successfully'));
    } catch (error: any) {
      if (error.message === 'Project not found') {
        res.status(404).json(createErrorResponse('Project not found'));
      } else if (error.message === 'Not authorized to update this project') {
        res.status(403).json(createErrorResponse('Not authorized to update this project'));
      } else {
        res.status(500).json(createErrorResponse('Failed to update project'));
      }
    }
  }

  static async deleteProject(req: AuthenticatedRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const userId = req.user?.sub;

      if (!userId) {
        res.status(401).json(createErrorResponse('User not authenticated'));
        return;
      }

      if (!validateId(id, res, 'Project ID')) {
        return;
      }

      await ProjectService.deleteProject(userId, id);
      res.json(createApiResponse({}, 'Project deleted successfully'));
    } catch (error: any) {
      if (error.message === 'Project not found') {
        res.status(404).json(createErrorResponse('Project not found'));
      } else if (error.message === 'Not authorized to delete this project') {
        res.status(403).json(createErrorResponse('Not authorized to delete this project'));
      } else {
        res.status(500).json(createErrorResponse('Failed to delete project'));
      }
    }
  }
}