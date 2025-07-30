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
    const unsubscribe = onAuthStateChanged(auth, (user) => {
      authStore.setUser(user);
      authStore.setLoading(false);
    });

    return () => unsubscribe();
  }, [authStore]);

  if (authStore.loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div>Loading...</div>
      </div>
    );
  }

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