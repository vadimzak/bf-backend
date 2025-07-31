import { v4 as uuidv4 } from 'uuid';
import { ScanCommand, PutCommand } from '@aws-sdk/lib-dynamodb';
import { dynamodb } from '../config/aws';
import { CreateItemRequest, Item } from '../types';
import { createLogger } from '../utils/logger';

const logger = createLogger('ITEMS SERVICE');

export class ItemService {
  private static getTableName(): string {
    return process.env.DYNAMODB_TABLE_NAME || 'gamani-items';
  }

  static async getItems(userId: string): Promise<Item[]> {
    logger.search('GET items - Starting');
    logger.search('User sub:', userId);
    logger.search('Table name:', this.getTableName());
    
    const params = {
      TableName: this.getTableName(),
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': userId
      }
    };

    logger.search('DynamoDB params:', JSON.stringify(params, null, 2));
    logger.search('About to call dynamodb.scan()...');
    
    const command = new ScanCommand(params);
    const result = await dynamodb.send(command);
    
    logger.success('DynamoDB scan completed successfully');
    logger.success('Result:', JSON.stringify(result, null, 2));
    
    return result.Items as Item[] || [];
  }

  static async createItem(userId: string, itemData: CreateItemRequest): Promise<Item> {
    const item: Item = {
      id: uuidv4(),
      userId,
      title: itemData.title,
      content: itemData.content,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const params = {
      TableName: this.getTableName(),
      Item: item
    };

    const putCommand = new PutCommand(params);
    await dynamodb.send(putCommand);
    
    return item;
  }
}