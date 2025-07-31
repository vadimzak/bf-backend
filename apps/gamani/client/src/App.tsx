import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { StoreContext, rootStore } from './stores';
import { observer } from 'mobx-react-lite';
import { useEffect } from 'react';
import { getCurrentUser } from 'aws-amplify/auth';
import './config/aws-config'; // Initialize Amplify
import HomePage from './pages/HomePage';
import LoginPage from './pages/LoginPage';
import DashboardPage from './pages/DashboardPage';
import SharedGamePage from './pages/SharedGamePage';
import { useStore } from './stores';

const AppContent = observer(() => {
  const { authStore } = useStore();

  useEffect(() => {
    console.log('🔧 [APP] Setting up Cognito auth state listener');
    authStore.setLoading(true);
    
    const checkAuthState = async () => {
      try {
        console.log('🔧 [APP] Checking current auth state...');
        
        // Add a small delay to allow Amplify to process OAuth callbacks
        await new Promise(resolve => setTimeout(resolve, 100));
        
        const user = await getCurrentUser();
        console.log('✅ [AUTH STATE] User authenticated:', { username: user.username, userId: user.userId });
        
        // Fetch user profile attributes
        const profile = await authStore.fetchUserProfile();
        
        authStore.setUser({
          userId: user.userId,
          username: user.username,
          profile: profile || undefined,
          signInDetails: user.signInDetails
        });
        authStore.setLoading(false);
      } catch (error) {
        console.log('🔧 [AUTH STATE] No authenticated user found, error:', error instanceof Error ? error.message : String(error));
        authStore.setUser(null);
        authStore.setLoading(false);
      }
    };

    checkAuthState();

    // Listen for auth state changes via URL changes (for OAuth redirects)
    const handleLocationChange = () => {
      console.log('🔧 [APP] Location changed, rechecking auth state');
      // Add a longer delay for OAuth callback processing
      setTimeout(() => {
        checkAuthState();
      }, 500);
    };

    // Also check when the page is focused (user returns from OAuth)
    const handleFocus = () => {
      console.log('🔧 [APP] Page focused, rechecking auth state');
      setTimeout(() => {
        checkAuthState();
      }, 500);
    };

    window.addEventListener('popstate', handleLocationChange);
    window.addEventListener('focus', handleFocus);
    
    return () => {
      console.log('🔧 [APP] Cleaning up auth state listener');
      window.removeEventListener('popstate', handleLocationChange);
      window.removeEventListener('focus', handleFocus);
    };
  }, [authStore]);

  if (authStore.loading) {
    console.log('🔧 [APP] Showing loading screen - auth state is being determined');
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div>Loading...</div>
      </div>
    );
  }

  console.log('🔧 [APP] Rendering app - authStore.isAuthenticated:', authStore.isAuthenticated);

  return (
    <Router>
      <div className="min-h-screen bg-background dark">
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/login" element={<LoginPage />} />
          <Route path="/dashboard" element={<DashboardPage />} />
          <Route path="/shared/:shareId" element={<SharedGamePage />} />
        </Routes>
      </div>
    </Router>
  );
});

function App() {
  return (
    <StoreContext.Provider value={rootStore}>
      <AppContent />
    </StoreContext.Provider>
  );
}

export default App;