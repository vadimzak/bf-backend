import { Response } from 'express';
import { createErrorResponse } from '@bf-backend/server-core';

export function validateRequired(fields: Record<string, any>, res: Response): boolean {
  for (const [key, value] of Object.entries(fields)) {
    if (!value || (typeof value === 'string' && !value.trim())) {
      res.status(400).json(createErrorResponse(`${key} is required`));
      return false;
    }
  }
  return true;
}

export function validateRole(role: string, res: Response): boolean {
  if (!['user', 'assistant'].includes(role)) {
    res.status(400).json(createErrorResponse('Role must be either "user" or "assistant"'));
    return false;
  }
  return true;
}

export function validateId(id: string, res: Response, fieldName: string = 'ID'): boolean {
  if (!id) {
    res.status(400).json(createErrorResponse(`${fieldName} is required`));
    return false;
  }
  return true;
}