import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { StoreContext, rootStore } from './stores';
import { observer } from 'mobx-react-lite';
import { useEffect } from 'react';
import { onAuthStateChanged } from 'firebase/auth';
import { auth } from './config/firebase';
import HomePage from './pages/HomePage';
import LoginPage from './pages/LoginPage';
import DashboardPage from './pages/DashboardPage';
import { useStore } from './stores';

const AppContent = observer(() => {
  const { authStore } = useStore();

  useEffect(() => {
    console.log('🔧 [APP] Setting up auth state listener');
    authStore.setLoading(true);
    
    // Set up auth state listener
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      console.log('🔥 [AUTH STATE] Auth state changed:', user ? `Signed in as ${user.email} (UID: ${user.uid})` : 'Signed out');
      console.log('🔥 [AUTH STATE] User object:', user ? { email: user.email, uid: user.uid, displayName: user.displayName } : null);
      authStore.setUser(user);
      authStore.setLoading(false);
      console.log('🔥 [AUTH STATE] AuthStore updated - isAuthenticated:', !!user);
    });

    // Ensure auth state is ready immediately
    auth.authStateReady().then(() => {
      console.log('🔥 [AUTH STATE] Initial auth state is ready');
      // If loading is still true, it means onAuthStateChanged hasn't fired yet
      // This can happen in some edge cases, so we manually check current user
      if (authStore.loading) {
        console.log('🔥 [AUTH STATE] Manually checking current user:', auth.currentUser?.email || 'null');
        authStore.setUser(auth.currentUser);
        authStore.setLoading(false);
      }
    }).catch((error) => {
      console.error('❌ [AUTH STATE] Error waiting for auth state ready:', error);
      authStore.setLoading(false);
    });

    return () => {
      console.log('🔧 [APP] Cleaning up auth state listener');
      unsubscribe();
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