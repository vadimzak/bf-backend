export interface CreateItemRequest {
  title: string;
  content: string;
}

export interface CreateProjectRequest {
  name: string;
  description?: string;
}

export interface UpdateProjectRequest {
  name?: string;
  description?: string;
}

export interface CreateMessageRequest {
  role: 'user' | 'assistant';
  content: string;
  gameCode?: string;
}

export interface AIGenerateRequest {
  prompt: string;
  conversation?: Array<{
    role: 'user' | 'assistant';
    content: string;
  }>;
  currentGame?: string;
}

export interface ShareGameRequest {
  title: string;
  content: string;
  description?: string;
}