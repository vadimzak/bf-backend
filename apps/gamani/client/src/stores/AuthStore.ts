import { makeAutoObservable } from 'mobx';
import { User, signOut } from 'firebase/auth';
import { auth } from '../config/firebase';

export class AuthStore {
  user: User | null = null;
  loading = false;
  error: string | null = null;

  constructor() {
    makeAutoObservable(this);
  }

  setUser(user: User | null) {
    console.log('🔄 [AUTHSTORE] setUser called with:', user ? { email: user.email, uid: user.uid } : null);
    this.user = user;
    console.log('🔄 [AUTHSTORE] isAuthenticated is now:', !!user);
  }

  setLoading(loading: boolean) {
    console.log('🔄 [AUTHSTORE] setLoading called with:', loading);
    this.loading = loading;
  }

  setError(error: string | null) {
    console.log('🔄 [AUTHSTORE] setError called with:', error);
    this.error = error;
  }

  get isAuthenticated() {
    return !!this.user;
  }

  async signOut() {
    console.log('🚪 [AUTHSTORE] signOut called');
    try {
      console.log('🚪 [AUTHSTORE] Calling Firebase signOut...');
      await signOut(auth);
      console.log('✅ [AUTHSTORE] Firebase signOut completed successfully');
      // The auth state listener will automatically call setUser(null)
    } catch (error) {
      console.error('❌ [AUTHSTORE] Sign out error:', error);
      this.setError('Failed to sign out');
    }
  }
}