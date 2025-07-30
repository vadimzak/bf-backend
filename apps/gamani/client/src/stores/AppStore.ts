import { makeAutoObservable } from 'mobx';

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

  async fetchItems() {
    this.setLoading(true);
    try {
      // API call logic will be implemented here
      this.setError(null);
    } catch (error) {
      this.setError(error instanceof Error ? error.message : 'Failed to fetch items');
    } finally {
      this.setLoading(false);
    }
  }

  async createItem(_title: string, _content: string) {
    this.setLoading(true);
    try {
      // API call logic will be implemented here
      this.setError(null);
    } catch (error) {
      this.setError(error instanceof Error ? error.message : 'Failed to create item');
    } finally {
      this.setLoading(false);
    }
  }
}