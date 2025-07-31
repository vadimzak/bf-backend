import { createContext, useContext } from 'react';
import { AuthStore } from './AuthStore';
import { AppStore } from './AppStore';
import { ProjectStore } from './ProjectStore';

export class RootStore {
  authStore: AuthStore;
  appStore: AppStore;
  projectStore: ProjectStore;

  constructor() {
    this.authStore = new AuthStore();
    this.appStore = new AppStore();
    this.projectStore = new ProjectStore();
  }
}

export const rootStore = new RootStore();
export const StoreContext = createContext(rootStore);

export const useStore = () => {
  const context = useContext(StoreContext);
  if (!context) {
    throw new Error('useStore must be used within a StoreProvider');
  }
  return context;
};