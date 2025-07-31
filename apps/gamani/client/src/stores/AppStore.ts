import { makeAutoObservable } from 'mobx';
import { fetchAuthSession, getCurrentUser } from 'aws-amplify/auth';

interface Item {
  id: string;
  title: string;
  content: string;
  createdAt: string;
  updatedAt: string;
}

export class AppStore {
  items: Item[] = [];
  loading = false;
  error: string | null = null;

  constructor() {
    makeAutoObservable(this);
  }

  setItems(items: Item[]) {
    this.items = items;
  }

  addItem(item: Item) {
    this.items.push(item);
  }

  setLoading(loading: boolean) {
    this.loading = loading;
  }

  setError(error: string | null) {
    this.error = error;
  }

  private async getAuthHeaders(): Promise<HeadersInit> {
    try {
      console.log('🔐 [APPSTORE] Getting auth headers...');
      
      // Get the current session directly from User Pool
      const session = await fetchAuthSession();
      console.log('🔐 [APPSTORE] Session obtained:', { 
        hasTokens: !!session.tokens,
        hasAccessToken: !!session.tokens?.accessToken 
      });
      
      const accessToken = session.tokens?.accessToken?.toString();
      
      if (!accessToken) {
        console.error('❌ [APPSTORE] No access token in session');
        throw new Error('No access token available');
      }

      console.log('✅ [APPSTORE] Access token obtained, length:', accessToken.length);
      
      return {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      };
    } catch (error) {
      console.error('❌ [APPSTORE] Failed to get auth token:', error);
      console.error('❌ [APPSTORE] Error details:', {
        name: error instanceof Error ? error.name : 'Unknown',
        message: error instanceof Error ? error.message : String(error),
        code: (error as any)?.code || 'unknown'
      });
      throw new Error('Authentication failed');
    }
  }

  async fetchItems() {
    this.setLoading(true);
    try {
      const headers = await this.getAuthHeaders();
      const response = await fetch('/api/protected/items', {
        method: 'GET',
        headers,
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        this.setItems(result.data.items || []);
      } else {
        throw new Error(result.error || 'Failed to fetch items');
      }
      
      this.setError(null);
    } catch (error) {
      console.error('Failed to fetch items:', error);
      this.setError(error instanceof Error ? error.message : 'Failed to fetch items');
    } finally {
      this.setLoading(false);
    }
  }

  async createItem(title: string, content: string) {
    this.setLoading(true);
    try {
      const headers = await this.getAuthHeaders();
      const response = await fetch('/api/protected/items', {
        method: 'POST',
        headers,
        body: JSON.stringify({ title, content }),
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const result = await response.json();
      if (result.success) {
        this.addItem(result.data.item);
      } else {
        throw new Error(result.error || 'Failed to create item');
      }
      
      this.setError(null);
    } catch (error) {
      console.error('Failed to create item:', error);
      this.setError(error instanceof Error ? error.message : 'Failed to create item');
    } finally {
      this.setLoading(false);
    }
  }
}