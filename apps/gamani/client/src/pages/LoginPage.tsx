import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { signInWithPopup } from 'firebase/auth';
import { auth, googleProvider } from '../config/firebase';
import { Navigate } from 'react-router-dom';

const LoginPage = observer(() => {
  const { authStore } = useStore();

  const handleGoogleSignIn = async () => {
    authStore.setLoading(true);
    try {
      await signInWithPopup(auth, googleProvider);
    } catch (error) {
      console.error('Sign in error:', error);
      authStore.setError('Failed to sign in');
    } finally {
      authStore.setLoading(false);
    }
  };

  if (authStore.isAuthenticated) {
    return <Navigate to="/dashboard" replace />;
  }

  return (
    <div className="container mx-auto px-4 py-16">
      <div className="max-w-md mx-auto">
        <div className="bg-card border border-border rounded-lg p-6">
          <h1 className="text-2xl font-bold text-center mb-6">Sign In to Gamani</h1>
          
          {authStore.error && (
            <div className="bg-destructive/10 border border-destructive/20 text-destructive rounded-md p-3 mb-4">
              {authStore.error}
            </div>
          )}

          <button
            onClick={handleGoogleSignIn}
            disabled={authStore.loading}
            className="w-full inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none ring-offset-background bg-primary text-primary-foreground hover:bg-primary/90 h-10 py-2 px-4"
          >
            {authStore.loading ? 'Signing in...' : 'Sign in with Google'}
          </button>
        </div>
      </div>
    </div>
  );
});

export default LoginPage;