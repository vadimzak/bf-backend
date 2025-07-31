import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { Navigate } from 'react-router-dom';
import { useEffect, useState } from 'react';
import { fetchHealthStatus, displayServiceStatus, HealthResponse } from '../utils/serverUtils';

const DashboardPage = observer(() => {
  const { authStore, appStore } = useStore();
  const [healthData, setHealthData] = useState<HealthResponse | null>(null);
  const [healthLoading, setHealthLoading] = useState(true);

  console.log('🔧 [DASHBOARD] DashboardPage rendering - authStore.isAuthenticated:', authStore.isAuthenticated);
  console.log('🔧 [DASHBOARD] AuthStore state:', { 
    user: authStore.user ? { 
      username: authStore.user.username, 
      userId: authStore.user.userId,
      profile: authStore.user.profile 
    } : null,
    loading: authStore.loading,
    error: authStore.error
  });

  useEffect(() => {
    if (authStore.isAuthenticated) {
      appStore.fetchItems();
    }
  }, [authStore.isAuthenticated, appStore]);

  useEffect(() => {
    const loadHealthData = async () => {
      try {
        const health = await fetchHealthStatus();
        setHealthData(health);
      } catch (error) {
        console.error('Failed to fetch health data:', error);
      } finally {
        setHealthLoading(false);
      }
    };

    loadHealthData();
    // Refresh health data every 30 seconds
    const interval = setInterval(loadHealthData, 30000);
    return () => clearInterval(interval);
  }, []);

  if (!authStore.isAuthenticated) {
    console.log('❌ [DASHBOARD] User is NOT authenticated, redirecting to login');
    return <Navigate to="/login" replace />;
  }

  console.log('✅ [DASHBOARD] User is authenticated, showing dashboard');

  const handleSignOut = () => {
    console.log('🚪 [DASHBOARD] User clicked sign out');
    authStore.signOut();
  };

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="flex justify-between items-center mb-8">
        <div>
          <h1 className="text-3xl font-bold">Dashboard</h1>
          <p className="text-muted-foreground">
            Welcome back, {authStore.user?.profile?.name || authStore.user?.username}
          </p>
        </div>
        <button
          onClick={handleSignOut}
          className="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none ring-offset-background border border-input bg-background hover:bg-accent hover:text-accent-foreground h-10 px-4 py-2"
        >
          Sign Out
        </button>
      </div>

      <div className="grid gap-6">
        <div className="bg-card border border-border rounded-lg p-6">
          <h2 className="text-xl font-semibold mb-4">Server Status</h2>
          
          {healthLoading && (
            <div>Loading server status...</div>
          )}

          {healthData && (
            <div className="space-y-3">
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                <div>
                  <span className="text-muted-foreground">App:</span>
                  <div className="font-mono">{healthData.data.name} v{healthData.data.version}</div>
                </div>
                <div>
                  <span className="text-muted-foreground">Uptime:</span>
                  <div className="font-mono">{healthData.data.uptimeFormatted}</div>
                </div>
                <div>
                  <span className="text-muted-foreground">Environment:</span>
                  <div className="font-mono">{healthData.data.environment}</div>
                </div>
                <div>
                  <span className="text-muted-foreground">Core:</span>
                  <div className="font-mono">{healthData.data.serverCore}</div>
                </div>
              </div>
              
              <div>
                <span className="text-muted-foreground">Services:</span>
                <div className="text-sm mt-1">
                  {displayServiceStatus(healthData.data.services)}
                </div>
              </div>
              
              <div className="text-xs text-muted-foreground">
                Last updated: {new Date(healthData.timestamp).toLocaleTimeString()}
              </div>
            </div>
          )}
        </div>

        <div className="bg-card border border-border rounded-lg p-6">
          <h2 className="text-xl font-semibold mb-4">Your Items</h2>
          
          {appStore.loading && (
            <div>Loading items...</div>
          )}

          {appStore.error && (
            <div className="bg-destructive/10 border border-destructive/20 text-destructive rounded-md p-3 mb-4">
              {appStore.error}
            </div>
          )}

          {!appStore.loading && !appStore.error && appStore.items.length === 0 && (
            <p className="text-muted-foreground">No items yet. Create your first item!</p>
          )}

          {appStore.items.map((item) => (
            <div key={item.id} className="border border-border rounded-md p-4 mb-4">
              <h3 className="font-semibold">{item.title}</h3>
              <p className="text-muted-foreground">{item.content}</p>
              <p className="text-sm text-muted-foreground mt-2">
                Created: {new Date(item.createdAt).toLocaleDateString()}
              </p>
            </div>
          ))}
        </div>

        <div className="bg-card border border-border rounded-lg p-6">
          <h2 className="text-xl font-semibold mb-4">AI Features</h2>
          <p className="text-muted-foreground">
            Google Generative AI integration coming soon...
          </p>
        </div>
      </div>
    </div>
  );
});

export default DashboardPage;