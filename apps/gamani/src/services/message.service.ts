import { v4 as uuidv4 } from 'uuid';
import { ScanCommand, PutCommand, GetCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { dynamodb } from '../config/aws';
import { CreateMessageRequest, Message } from '../types';
import { createLogger } from '../utils/logger';

const logger = createLogger('CHAT SERVICE');

export class MessageService {
  private static getMessagesTableName(): string {
    return process.env.DYNAMODB_MESSAGES_TABLE || 'gamani-messages';
  }

  private static getProjectsTableName(): string {
    return process.env.DYNAMODB_PROJECTS_TABLE || 'gamani-projects';
  }

  static async getMessages(userId: string, projectId: string): Promise<Message[]> {
    logger.chat('GET messages - Starting');
    
    await this.verifyProjectAccess(userId, projectId);

    const params = {
      TableName: this.getMessagesTableName(),
      FilterExpression: 'projectId = :projectId',
      ExpressionAttributeValues: {
        ':projectId': projectId
      }
    };

    logger.chat('Fetching messages for project:', projectId);
    
    const command = new ScanCommand(params);
    const result = await dynamodb.send(command);
    
    const messages = (result.Items || []).sort((a, b) => 
      new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
    );
    
    logger.success('Messages retrieved successfully, count:', messages.length);
    return messages as Message[];
  }

  static async createMessage(userId: string, projectId: string, messageData: CreateMessageRequest): Promise<Message> {
    logger.chat('POST messages - Starting');
    
    await this.verifyProjectAccess(userId, projectId);

    const message: Message = {
      id: uuidv4(),
      projectId,
      role: messageData.role,
      content: messageData.content,
      ...(messageData.gameCode && { gameCode: messageData.gameCode }),
      timestamp: new Date().toISOString()
    };

    const params = {
      TableName: this.getMessagesTableName(),
      Item: message
    };

    logger.chat('Saving message:', JSON.stringify(message, null, 2));
    
    const putCommand = new PutCommand(params);
    await dynamodb.send(putCommand);
    
    logger.success('Message saved successfully');
    return message;
  }

  static async clearMessages(userId: string, projectId: string): Promise<number> {
    logger.chat('DELETE messages - Starting');
    
    await this.verifyProjectAccess(userId, projectId);

    const scanParams = {
      TableName: this.getMessagesTableName(),
      FilterExpression: 'projectId = :projectId',
      ExpressionAttributeValues: {
        ':projectId': projectId
      }
    };

    const scanCommand = new ScanCommand(scanParams);
    const scanResult = await dynamodb.send(scanCommand);
    const messages = scanResult.Items || [];

    logger.chat('Found', messages.length, 'messages to delete for project:', projectId);

    const deletePromises = messages.map(message => {
      const deleteParams = {
        TableName: this.getMessagesTableName(),
        Key: { id: message.id }
      };
      const deleteCommand = new DeleteCommand(deleteParams);
      return dynamodb.send(deleteCommand);
    });

    await Promise.all(deletePromises);
    
    logger.success('All messages deleted successfully');
    return messages.length;
  }

  private static async verifyProjectAccess(userId: string, projectId: string): Promise<void> {
    const projectParams = {
      TableName: this.getProjectsTableName(),
      Key: { id: projectId }
    };

    const projectGetCommand = new GetCommand(projectParams);
    const projectResult = await dynamodb.send(projectGetCommand);
    
    if (!projectResult.Item) {
      throw new Error('Project not found');
    }

    if (projectResult.Item.userId !== userId) {
      throw new Error('Not authorized to access this project');
    }
  }
}