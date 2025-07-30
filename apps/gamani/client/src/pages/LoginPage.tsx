import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { signInWithPopup } from 'firebase/auth';
import { auth, googleProvider } from '../config/firebase';
import { Navigate } from 'react-router-dom';
import { useEffect } from 'react';

const LoginPage = observer(() => {
  const { authStore } = useStore();

  console.log('🔧 [LOGIN] LoginPage rendering - authStore.isAuthenticated:', authStore.isAuthenticated);
  console.log('🔧 [LOGIN] AuthStore state:', { 
    user: authStore.user ? { email: authStore.user.email, uid: authStore.user.uid } : null,
    loading: authStore.loading,
    error: authStore.error
  });

  // Clear error when navigating to login page
  useEffect(() => {
    authStore.setError(null);
  }, [authStore]);

  const handleGoogleSignIn = async () => {
    console.log('🚀 [SIGNIN] Starting Google popup sign in');
    console.log('🚀 [SIGNIN] Current URL:', window.location.href);
    console.log('🚀 [SIGNIN] Firebase Auth config:', {
      app: auth.app.name,
      authDomain: auth.app.options.authDomain,
      projectId: auth.app.options.projectId
    });
    
    authStore.setLoading(true);
    authStore.setError(null);
    
    try {
      console.log('🚀 [POPUP] Using popup authentication (works everywhere!)');
      console.log('🚀 [POPUP] Google provider config:', {
        providerId: googleProvider.providerId
      });
      
      const result = await signInWithPopup(auth, googleProvider);
      console.log('✅ [POPUP] Sign in successful:', result.user?.email);
      console.log('✅ [POPUP] User UID:', result.user?.uid);
      
      // The auth state listener in App.tsx will handle setting the user,
      // but we can also set it directly for immediate UI update
      authStore.setUser(result.user);
      
    } catch (error: any) {
      console.error('❌ [POPUP] Popup sign in failed:', error);
      console.error('❌ [POPUP] Error code:', error.code);
      console.error('❌ [POPUP] Error message:', error.message);
      console.error('❌ [POPUP] Error details:', {
        name: error.name,
        stack: error.stack?.substring(0, 200),
        customData: error.customData
      });
      
      // Handle specific popup errors
      if (error.code === 'auth/popup-closed-by-user') {
        authStore.setError('Sign in popup closed. Please try again and make sure popups are allowed.');
      } else if (error.code === 'auth/popup-blocked') {
        authStore.setError('Popup was blocked by browser. Please allow popups for this site.');
      } else if (error.code === 'auth/unauthorized-domain') {
        authStore.setError('This domain is not authorized. Please contact support.');
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