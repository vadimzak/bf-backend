import { makeAutoObservable } from 'mobx';
import { User } from 'firebase/auth';

export class AuthStore {
  user: User | null = null;
  loading = false;
  error: string | null = null;

  constructor() {
    makeAutoObservable(this);
  }

  setUser(user: User | null) {
    this.user = user;
  }

  setLoading(loading: boolean) {
    this.loading = loading;
  }

  setError(error: string | null) {
    this.error = error;
  }

  get isAuthenticated() {
    return !!this.user;
  }

  async signOut() {
    // Firebase sign out logic will be implemented here
    this.setUser(null);
  }
}