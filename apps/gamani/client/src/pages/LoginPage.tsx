import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { signInWithPopup } from 'firebase/auth';
import { auth, googleProvider } from '../config/firebase';
import { Navigate } from 'react-router-dom';
import { useEffect } from 'react';

const LoginPage = observer(() => {
  const { authStore } = useStore();

  console.log('🔧 [LOGIN] LoginPage rendering - authStore.isAuthenticated:', authStore.isAuthenticated);

  // Clear error when navigating to login page
  useEffect(() => {
    authStore.setError(null);
  }, [authStore]);

  const handleGoogleSignIn = async () => {
    console.log('🚀 [SIGNIN] Starting Google popup sign in');
    
    authStore.setLoading(true);
    authStore.setError(null);
    
    try {
      console.log('🚀 [POPUP] Attempting signInWithPopup...');
      const result = await signInWithPopup(auth, googleProvider);
      console.log('✅ [POPUP] Sign in successful:', result.user?.email);
      
      // The auth state listener will handle the rest
      
    } catch (error: any) {
      console.error('❌ [POPUP] Sign in failed:', error);
      console.error('❌ [POPUP] Error code:', error.code);
      console.error('❌ [POPUP] Error message:', error.message);
      
      // Handle specific errors
      if (error.code === 'auth/popup-closed-by-user') {
        authStore.setError('Sign in was cancelled. Please try again.');
      } else if (error.code === 'auth/popup-blocked') {
        authStore.setError('Popup was blocked by your browser. Please allow popups and try again.');
      } else if (error.code === 'auth/unauthorized-domain') {
        authStore.setError('This domain is not authorized. Please contact support.');
      } else if (error.code === 'auth/configuration-not-found') {
        authStore.setError('Firebase configuration error. Please contact support.');
      } else {
        authStore.setError(`Failed to sign in: ${error.message}`);
      }
      
      authStore.setLoading(false);
    }
  };


  // const handleClearSession = async () => {
  //   console.log('🧹 [CLEAR] Starting session clear');
  //   try {
  //     await authStore.signOut();
  //     console.log('✅ [CLEAR] Session cleared successfully');
  //   } catch (error) {
  //     console.error('❌ [CLEAR] Clear session error:', error);
  //   }
  // };


  if (authStore.isAuthenticated) {
    console.log('✅ [LOGIN] User is authenticated, redirecting to dashboard');
    console.log('✅ [LOGIN] User details:', { email: authStore.user?.email, uid: authStore.user?.uid });
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
            {authStore.loading ? 'Signing in...' : 'Sign in with Google'}
          </button>
        </div>
      </div>
    </div>
  );
});

export default LoginPage;