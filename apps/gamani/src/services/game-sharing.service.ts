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
    await dynamodb.send(shareGameCommand);

    return {
      shareId,
      shareUrl: `https://${host}/shared/${shareId}`
    };
  }

  static async getSharedGame(shareId: string): Promise<SharedGame> {
    const getSharedGameCommand = new GetCommand({
      TableName: this.getTableName(),
      Key: { shareId }
    });
    const result = await dynamodb.send(getSharedGameCommand);

    if (!result.Item) {
      throw new Error('Shared game not found');
    }

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

    return gameData;
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