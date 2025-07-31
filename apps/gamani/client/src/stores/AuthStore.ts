import { makeAutoObservable } from 'mobx';
import { signOut, fetchUserAttributes } from 'aws-amplify/auth';

interface UserProfile {
  email?: string;
  name?: string;
  given_name?: string;
  family_name?: string;
  picture?: string;
}

interface CognitoUser {
  userId: string;
  username: string;
  profile?: UserProfile;
  signInDetails?: any;
}

export class AuthStore {
  user: CognitoUser | null = null;
  loading = false;
  error: string | null = null;

  constructor() {
    makeAutoObservable(this);
  }

  setUser(user: CognitoUser | null) {
    console.log('🔄 [AUTHSTORE] setUser called with:', user ? { username: user.username, userId: user.userId, profile: user.profile } : null);
    this.user = user;
    console.log('🔄 [AUTHSTORE] isAuthenticated is now:', !!user);
  }

  async fetchUserProfile(): Promise<UserProfile | null> {
    try {
      console.log('🔄 [AUTHSTORE] Fetching user attributes...');
      const attributes = await fetchUserAttributes();
      console.log('✅ [AUTHSTORE] Raw user attributes fetched:', JSON.stringify(attributes, null, 2));
      
      const profile: UserProfile = {
        email: attributes.email,
        name: attributes.name,
        given_name: attributes.given_name,
        family_name: attributes.family_name,
        picture: attributes.picture
      };
      
      console.log('✅ [AUTHSTORE] Processed profile:', JSON.stringify(profile, null, 2));
      return profile;
    } catch (error) {
      console.error('❌ [AUTHSTORE] Error fetching user attributes:', error);
      return null;
    }
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
      console.log('🚪 [AUTHSTORE] Calling Cognito signOut...');
      await signOut();
      console.log('✅ [AUTHSTORE] Cognito signOut completed successfully');
      this.setUser(null);
    } catch (error) {
      console.error('❌ [AUTHSTORE] Sign out error:', error);
      this.setError('Failed to sign out');
    }
  }
}