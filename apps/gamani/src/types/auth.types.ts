import { Request } from 'express';

export interface AuthenticatedRequest extends Request {
  user?: {
    sub: string;
    username: string;
    email?: string;
    email_verified?: boolean;
    'cognito:username'?: string;
  };
}

export interface CognitoUserPayload {
  sub: string;
  username?: string;
  email?: string;
  email_verified?: boolean;
  'cognito:username'?: string;
  client_id?: string;
}