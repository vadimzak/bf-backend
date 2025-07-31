import { v4 as uuidv4 } from 'uuid';
import { PutCommand, GetCommand, ScanCommand, UpdateCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { dynamodb } from '../config/aws';
import { ShareGameRequest, SharedGame } from '../types';
import { createLogger } from '../utils/logger';

const logger = createLogger('SHARING SERVICE');

export class GameSharingService {
  private static getTableName(): string {
    return 'gamani-shared-games';
  }

  static async shareGame(userId: string, gameData: ShareGameRequest, host: string): Promise<{ shareId: string; shareUrl: string }> {
    try {
      logger.info('Starting game share process', { userId, host, titleLength: gameData.title?.length, contentLength: gameData.content?.length });
      
      const shareId = uuidv4();
      const now = new Date().toISOString();

      const sharedGame: SharedGame = {
        shareId,
        userId,
        title: gameData.title,
        content: gameData.content,
        description: gameData.description || '',
        createdAt: now,
        accessCount: 0
      };

      const shareGameCommand = new PutCommand({
        TableName: this.getTableName(),
        Item: sharedGame
      });
      
      logger.info('Saving shared game to DynamoDB', { shareId, tableName: this.getTableName() });
      await dynamodb.send(shareGameCommand);
      
      const shareUrl = `https://${host}/shared/${shareId}`;
      logger.info('Game shared successfully', { shareId, shareUrl });

      return {
        shareId,
        shareUrl
      };
    } catch (error) {
      logger.error('Failed to share game', error);
      throw error;
    }
  }

  static async getSharedGame(shareId: string): Promise<SharedGame> {
    try {
      logger.info('Retrieving shared game', { shareId, tableName: this.getTableName() });
      
      const getSharedGameCommand = new GetCommand({
        TableName: this.getTableName(),
        Key: { shareId }
      });
      const result = await dynamodb.send(getSharedGameCommand);

      logger.info('DynamoDB query result', { shareId, hasItem: !!result.Item });

      if (!result.Item) {
        logger.warning('Shared game not found', { shareId });
        throw new Error('Shared game not found');
      }

      // Increment access count
      logger.info('Incrementing access count', { shareId, currentCount: result.Item.accessCount || 0 });
      const incrementCommand = new UpdateCommand({
        TableName: this.getTableName(),
        Key: { shareId },
        UpdateExpression: 'SET accessCount = accessCount + :inc',
        ExpressionAttributeValues: {
          ':inc': 1
        }
      });
      await dynamodb.send(incrementCommand);

      const gameData = {
        shareId: result.Item.shareId,
        title: result.Item.title,
        content: result.Item.content,
        description: result.Item.description,
        createdAt: result.Item.createdAt,
        accessCount: (result.Item.accessCount || 0) + 1
      } as SharedGame;

      logger.info('Successfully retrieved shared game', { shareId, title: gameData.title, accessCount: gameData.accessCount });
      return gameData;
    } catch (error) {
      logger.error('Failed to retrieve shared game', { shareId, error });
      throw error;
    }
  }

  static async getUserSharedGames(userId: string): Promise<Partial<SharedGame>[]> {
    const scanSharedGamesCommand = new ScanCommand({
      TableName: this.getTableName(),
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': userId
      }
    });
    const result = await dynamodb.send(scanSharedGamesCommand);

    const sharedGames = result.Items?.map(item => ({
      shareId: item.shareId,
      title: item.title,
      description: item.description,
      createdAt: item.createdAt,
      accessCount: item.accessCount || 0
    })) || [];

    return sharedGames;
  }

  static async deleteSharedGame(userId: string, shareId: string): Promise<void> {
    const getSharedGameCommand = new GetCommand({
      TableName: this.getTableName(),
      Key: { shareId }
    });
    const result = await dynamodb.send(getSharedGameCommand);

    if (!result.Item) {
      throw new Error('Shared game not found');
    }

    if (result.Item.userId !== userId) {
      throw new Error('Not authorized to delete this shared game');
    }

    const deleteSharedGameCommand = new DeleteCommand({
      TableName: this.getTableName(),
      Key: { shareId }
    });
    await dynamodb.send(deleteSharedGameCommand);
  }
}