import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { signInWithRedirect } from 'aws-amplify/auth';
import { Navigate } from 'react-router-dom';
import { useEffect } from 'react';

const LoginPage = observer(() => {
  const { authStore } = useStore();

  console.log('🔧 [LOGIN] LoginPage rendering - authStore.isAuthenticated:', authStore.isAuthenticated);

  // Check for OAuth callback and clear error when navigating to login page
  useEffect(() => {
    const checkOAuthCallback = async () => {
      // Check if we have OAuth callback parameters in the URL
      const urlParams = new URLSearchParams(window.location.search);
      const code = urlParams.get('code');
      const state = urlParams.get('state');
      
      if (code) {
        console.log('🔧 [OAUTH] OAuth callback detected with code:', code.substring(0, 10) + '...');
        console.log('🔧 [OAUTH] State parameter:', state);
        
        // Clear the URL parameters to avoid processing again
        window.history.replaceState({}, document.title, window.location.pathname);
        
        // Let Amplify handle the token exchange - it should automatically detect the callback
        // and update the auth state. We just need to wait for the auth state to update.
        console.log('🔧 [OAUTH] Waiting for Amplify to process OAuth callback...');
        return;
      }
      
      console.log('🔧 [LOGIN] No OAuth callback detected, normal login page load');
    };

    checkOAuthCallback();
    authStore.setError(null);
  }, [authStore]);

  const handleGoogleSignIn = async () => {
    console.log('🚀 [SIGNIN] Starting Google OAuth sign in');
    
    authStore.setLoading(true);
    authStore.setError(null);
    
    try {
      console.log('🚀 [COGNITO] Attempting signInWithRedirect...');
      await signInWithRedirect({ provider: 'Google' });
      console.log('✅ [COGNITO] Redirect initiated successfully');
      // User will be redirected to Google, then back to our app
      
    } catch (error: any) {
      console.error('❌ [COGNITO] Sign in failed:', error);
      console.error('❌ [COGNITO] Error message:', error.message);
      
      // Handle specific errors
      if (error.message?.includes('unauthorized')) {
        authStore.setError('This domain is not authorized. Please contact support.');
      } else if (error.message?.includes('configuration')) {
        authStore.setError('Authentication configuration error. Please contact support.');
      } else {
        authStore.setError(`Failed to start sign in: ${error.message}`);
      }
      
      authStore.setLoading(false);
    }
  };

  if (authStore.isAuthenticated) {
    console.log('✅ [LOGIN] User is authenticated, redirecting to dashboard');
    console.log('✅ [LOGIN] User details:', { username: authStore.user?.username, userId: authStore.user?.userId });
    return <Navigate to="/dashboard" replace />;
  }

  console.log('🔧 [LOGIN] User is NOT authenticated, showing login form');

  return (
    <div className="container mx-auto px-4 py-16">
      <div className="max-w-md mx-auto">
        <div className="bg-card border border-border rounded-lg p-6">
          <h1 className="text-2xl font-bold text-center mb-6">Sign In to Gamani 3</h1>
          
          {authStore.error && (
            <div className="bg-destructive/10 border border-destructive/20 text-destructive rounded-md p-3 mb-4">
              {authStore.error}
            </div>
          )}

          <button
            onClick={handleGoogleSignIn}
            disabled={authStore.loading}
            className="w-full inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none ring-offset-background bg-primary text-primary-foreground hover:bg-primary/90 h-10 py-2 px-4 mb-2"
          >
            {authStore.loading ? 'Redirecting to Google...' : 'Sign in with Google'}
          </button>
        </div>
      </div>
    </div>
  );
});

export default LoginPage;