import { fetchAuthSession } from 'aws-amplify/auth';

/**
 * Get authentication headers for API requests
 * Uses mock authentication if enabled, otherwise uses Cognito
 */
export const getAuthHeaders = async (): Promise<HeadersInit> => {
  const mockAuthEnabled = localStorage.getItem('mockAuthEnabled') === 'true';
  
  if (mockAuthEnabled) {
    console.log('🎭 Using mock authentication headers');
    return {
      'Authorization': 'Mock admin',
      'X-Mock-User': 'admin',
      'Content-Type': 'application/json',
    };
  }
  
  try {
    const session = await fetchAuthSession();
    const accessToken = session.tokens?.accessToken?.toString();
    
    if (!accessToken) {
      throw new Error('No access token available');
    }

    return {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    };
  } catch (error) {
    console.error('Failed to get auth token:', error);
    throw new Error('Authentication failed');
  }
};