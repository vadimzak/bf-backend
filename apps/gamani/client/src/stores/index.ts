import { createContext, useContext } from 'react';
import { AuthStore } from './AuthStore';
import { AppStore } from './AppStore';

export class RootStore {
  authStore: AuthStore;
  appStore: AppStore;

  constructor() {
    this.authStore = new AuthStore();
    this.appStore = new AppStore();
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