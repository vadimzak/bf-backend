import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { Navigate } from 'react-router-dom';

const HomePage = observer(() => {
  const { authStore } = useStore();

  if (authStore.isAuthenticated) {
    return <Navigate to="/dashboard" replace />;
  }

  return (
    <div className="container mx-auto px-4 py-16">
      <div className="max-w-4xl mx-auto text-center">
        <h1 className="text-4xl font-bold text-foreground mb-8">
          Welcome to Gamani
        </h1>
        <p className="text-xl text-muted-foreground mb-8">
          A modern full-stack application built with React, TypeScript, and MobX
        </p>
        <div className="space-x-4">
          <a
            href="/login"
            className="inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 disabled:pointer-events-none ring-offset-background bg-primary text-primary-foreground hover:bg-primary/90 h-10 py-2 px-4"
          >
            Get Started
          </a>
        </div>
      </div>
    </div>
  );
});

export default HomePage;