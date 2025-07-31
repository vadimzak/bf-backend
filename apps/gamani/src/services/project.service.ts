import { v4 as uuidv4 } from 'uuid';
import { ScanCommand, PutCommand, GetCommand, UpdateCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { dynamodb } from '../config/aws';
import { CreateProjectRequest, UpdateProjectRequest, Project } from '../types';
import { createLogger } from '../utils/logger';

const logger = createLogger('PROJECTS SERVICE');

export class ProjectService {
  private static getTableName(): string {
    return process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects';
  }

  static async getProjects(userId: string): Promise<Project[]> {
    logger.search('GET projects - Starting');
    logger.search('User sub:', userId);
    
    const params = {
      TableName: this.getTableName(),
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': userId
      }
    };

    logger.search('DynamoDB params:', JSON.stringify(params, null, 2));
    
    const command = new ScanCommand(params);
    const result = await dynamodb.send(command);
    
    logger.success('DynamoDB scan completed successfully');
    logger.success('Result:', JSON.stringify(result, null, 2));
    
    return result.Items as Project[] || [];
  }

  static async createProject(userId: string, projectData: CreateProjectRequest): Promise<Project> {
    logger.debug('POST projects - Starting');
    
    const project: Project = {
      id: uuidv4(),
      userId,
      name: projectData.name.trim(),
      description: projectData.description?.trim() || '',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const params = {
      TableName: this.getTableName(),
      Item: project
    };

    logger.debug('Creating project:', JSON.stringify(project, null, 2));
    
    const putCommand = new PutCommand(params);
    await dynamodb.send(putCommand);
    
    logger.success('Project created successfully');
    return project;
  }

  static async updateProject(userId: string, id: string, updateData: UpdateProjectRequest): Promise<Project> {
    logger.debug('PUT projects/:id - Starting');
    
    const existingProject = await this.getProjectById(id);
    if (!existingProject) {
      throw new Error('Project not found');
    }

    if (existingProject.userId !== userId) {
      throw new Error('Not authorized to update this project');
    }

    const updateExpression = [];
    const expressionAttributeValues: any = {};
    const expressionAttributeNames: any = {};

    if (updateData.name !== undefined) {
      updateExpression.push('#name = :name');
      expressionAttributeNames['#name'] = 'name';
      expressionAttributeValues[':name'] = updateData.name.trim();
    }

    if (updateData.description !== undefined) {
      updateExpression.push('description = :description');
      expressionAttributeValues[':description'] = updateData.description.trim();
    }

    updateExpression.push('updatedAt = :updatedAt');
    expressionAttributeValues[':updatedAt'] = new Date().toISOString();

    const updateParams = {
      TableName: this.getTableName(),
      Key: { id },
      UpdateExpression: `SET ${updateExpression.join(', ')}`,
      ExpressionAttributeValues: expressionAttributeValues,
      ...(Object.keys(expressionAttributeNames).length > 0 && { ExpressionAttributeNames: expressionAttributeNames }),
      ReturnValues: 'ALL_NEW' as const
    };

    logger.debug('Updating project:', JSON.stringify(updateParams, null, 2));
    
    const updateCommand = new UpdateCommand(updateParams);
    const result = await dynamodb.send(updateCommand);
    
    logger.success('Project updated successfully');
    return result.Attributes as Project;
  }

  static async deleteProject(userId: string, id: string): Promise<void> {
    logger.debug('DELETE projects/:id - Starting');
    
    const existingProject = await this.getProjectById(id);
    if (!existingProject) {
      throw new Error('Project not found');
    }

    if (existingProject.userId !== userId) {
      throw new Error('Not authorized to delete this project');
    }

    const deleteParams = {
      TableName: this.getTableName(),
      Key: { id }
    };

    logger.debug('Deleting project:', id);
    
    const deleteCommand = new DeleteCommand(deleteParams);
    await dynamodb.send(deleteCommand);
    
    logger.success('Project deleted successfully');
  }

  private static async getProjectById(id: string): Promise<Project | null> {
    const getParams = {
      TableName: this.getTableName(),
      Key: { id }
    };

    const getCommand = new GetCommand(getParams);
    const result = await dynamodb.send(getCommand);
    
    return result.Item as Project || null;
  }
}