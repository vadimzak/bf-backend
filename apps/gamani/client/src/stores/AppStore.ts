import { makeAutoObservable } from 'mobx';
import { getAuthHeaders } from '../utils/auth-headers';

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

  async getAuthHeaders(): Promise<HeadersInit> {
    return getAuthHeaders();
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