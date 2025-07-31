export interface Item {
  id: string;
  userId: string;
  title: string;
  content: string;
  createdAt: string;
  updatedAt: string;
}

export interface Project {
  id: string;
  userId: string;
  name: string;
  description: string;
  createdAt: string;
  updatedAt: string;
}

export interface Message {
  id: string;
  projectId: string;
  role: 'user' | 'assistant';
  content: string;
  gameCode?: string;
  timestamp: string;
}

export interface SharedGame {
  shareId: string;
  userId: string;
  title: string;
  content: string;
  description: string;
  createdAt: string;
  accessCount: number;
}

export interface HealthData {
  status: string;
  uptime: number;
  uptimeFormatted: string;
  version: string;
  gitCommit: string;
  buildTime: string;
  deployedBy: string;
  serverCore: any;
  services: {
    cognito: boolean;
    dynamodb: boolean;
    googleAI: boolean;
  };
}