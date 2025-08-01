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
  mockAuthEnabled = false;

  constructor() {
    makeAutoObservable(this);
    // Check if mock authentication is enabled
    this.mockAuthEnabled = localStorage.getItem('mockAuthEnabled') === 'true' || 
                          (import.meta.env?.NODE_ENV === 'development' && 
                           window.location.search.includes('mock=true'));
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
    if (this.mockAuthEnabled) {
      const mockUser = localStorage.getItem('mockUser');
      return !!this.user || !!mockUser;
    }
    return !!this.user;
  }

  setupMockAuth(mockUserData: any) {
    console.log('🎭 [AUTHSTORE] Setting up mock authentication with:', mockUserData);
    this.mockAuthEnabled = true;
    localStorage.setItem('mockAuthEnabled', 'true');
    localStorage.setItem('mockUser', JSON.stringify(mockUserData));
    
    // Convert mock user data to CognitoUser format
    const cognitoUser: CognitoUser = {
      userId: mockUserData.sub,
      username: mockUserData.username,
      profile: {
        email: mockUserData.email,
        name: mockUserData.username
      }
    };
    
    this.setUser(cognitoUser);
    this.setLoading(false);
    console.log('✅ [AUTHSTORE] Mock authentication setup complete');
  }

  async signOut() {
    console.log('🚪 [AUTHSTORE] signOut called');
    try {
      if (this.mockAuthEnabled) {
        console.log('🚪 [AUTHSTORE] Mock sign out...');
        localStorage.removeItem('mockAuthEnabled');
        localStorage.removeItem('mockUser');
        this.mockAuthEnabled = false;
      } else {
        console.log('🚪 [AUTHSTORE] Calling Cognito signOut...');
        await signOut();
        console.log('✅ [AUTHSTORE] Cognito signOut completed successfully');
      }
      this.setUser(null);
    } catch (error) {
      console.error('❌ [AUTHSTORE] Sign out error:', error);
      this.setError('Failed to sign out');
    }
  }
}