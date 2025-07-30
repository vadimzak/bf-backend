import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { Navigate } from 'react-router-dom';
import { useEffect } from 'react';

const DashboardPage = observer(() => {
  const { authStore, appStore } = useStore();

  useEffect(() => {
    if (authStore.isAuthenticated) {
      appStore.fetchItems();
    }
  }, [authStore.isAuthenticated, appStore]);

  if (!authStore.isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  const handleSignOut = () => {
    authStore.signOut();
  };

  return (
    <div className="container mx-auto px-4 py-8">
      <div className="flex justify-between items-center mb-8">
        <div>
          <h1 className="text-3xl font-bold">Dashboard</h1>
          <p className="text-muted-foreground">
            Welcome back, {authStore.user?.displayName || authStore.user?.email}
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