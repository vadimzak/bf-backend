import { makeAutoObservable } from 'mobx';
import { getAuthHeaders } from '../utils/auth-headers';

export interface ChatMessage {
  id: string;
  projectId: string;
  role: 'user' | 'assistant';
  content: string;
  gameCode?: string; // If the message contains generated game code
  timestamp: string;
}

export class ChatStore {
  messages: ChatMessage[] = [];
  loading = false;
  error: string | null = null;
  currentProjectId: string | null = null;

  constructor() {
    makeAutoObservable(this);
  }

  setMessages(messages: ChatMessage[]) {
    this.messages = messages;
  }

  addMessage(message: ChatMessage) {
    this.messages.push(message);
  }

  replaceMessage(oldMessageId: string, newMessage: ChatMessage) {
    const messageIndex = this.messages.findIndex(m => m.id === oldMessageId);
    if (messageIndex !== -1) {
      this.messages[messageIndex] = newMessage;
    }
  }

  clearMessages() {
    this.messages = [];
  }

  setCurrentProjectId(projectId: string | null) {
    if (this.currentProjectId !== projectId) {
      this.currentProjectId = projectId;
      this.messages = []; // Clear messages when switching projects
      if (projectId) {
        this.fetchMessages(projectId);
      }
    }
  }

  setLoading(loading: boolean) {
    this.loading = loading;
  }

  setError(error: string | null) {
    this.error = error;
  }

  async getAuthHeaders(): Promise<HeadersInit> {
    return getAuthHeaders();
  }

  async fetchMessages(projectId: string) {
    if (!projectId) return;
    
    this.setLoading(true);
    try {
      const headers = await this.getAuthHeaders();
      const response = await fetch(`/api/protected/projects/${projectId}/messages`, {
        method: 'GET',
        headers,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        this.setMessages(result.data.messages || []);
      } else {
        throw new Error(result.error || 'Failed to fetch messages');
      }
      
      this.setError(null);
    } catch (error) {
      console.error('Failed to fetch messages:', error);
      this.setError(error instanceof Error ? error.message : 'Failed to fetch messages');
    } finally {
      this.setLoading(false);
    }
  }

  async saveMessage(projectId: string, role: 'user' | 'assistant', content: string, gameCode?: string, skipAddToUI = false) {
    if (!projectId) return null;

    try {
      const headers = await this.getAuthHeaders();
      const response = await fetch(`/api/protected/projects/${projectId}/messages`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ role, content, gameCode }),
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        if (!skipAddToUI) {
          this.addMessage(result.data.message);
        }
        return result.data.message;
      } else {
        throw new Error(result.error || 'Failed to save message');
      }
    } catch (error) {
      console.error('Failed to save message:', error);
      this.setError(error instanceof Error ? error.message : 'Failed to save message');
      throw error;
    }
  }

  async clearChatHistory(projectId: string) {
    if (!projectId) return;

    this.setLoading(true);
    try {
      const headers = await this.getAuthHeaders();
      const response = await fetch(`/api/protected/projects/${projectId}/messages`, {
        method: 'DELETE',
        headers,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        this.clearMessages();
      } else {
        throw new Error(result.error || 'Failed to clear messages');
      }
      
      this.setError(null);
    } catch (error) {
      console.error('Failed to clear messages:', error);
      this.setError(error instanceof Error ? error.message : 'Failed to clear messages');
      throw error;
    } finally {
      this.setLoading(false);
    }
  }

  // Get messages for the current project
  get currentMessages() {
    return this.messages.filter(m => m.projectId === this.currentProjectId);
  }

  // Check if there are any messages
  get hasMessages() {
    return this.currentMessages.length > 0;
  }
}