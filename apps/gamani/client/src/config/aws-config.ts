import { Amplify } from 'aws-amplify';

const awsConfig = {
  Auth: {
    Cognito: {
      userPoolId: 'il-central-1_aJg6S7Rl3',
      userPoolClientId: '1qa3m3ok5i8ehg0ef8jg3fnff6',
      // Removed identityPoolId - using User Pool tokens directly for API auth
      loginWith: {
        oauth: {
          domain: 'gamani-auth.auth.il-central-1.amazoncognito.com',
          scopes: ['openid', 'email', 'profile'],
          redirectSignIn: ['https://gamani.vadimzak.com/login', 'http://localhost:5173/login'],
          redirectSignOut: ['https://gamani.vadimzak.com/login', 'http://localhost:5173/login'],
          responseType: 'code',
          providers: ['Google']
        }
      }
    }
  }
} as any; // Temporary fix for typing issues

console.log('🔧 [AWS] Initializing Amplify with Cognito User Pool:', awsConfig.Auth.Cognito.userPoolId);

// Configure Amplify
Amplify.configure(awsConfig);

console.log('✅ [AWS] Amplify configured successfully');

export default awsConfig;