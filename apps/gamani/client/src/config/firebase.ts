import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider, setPersistence, browserLocalPersistence } from 'firebase/auth';

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID,
  appId: import.meta.env.VITE_FIREBASE_APP_ID
};

// Debug logging for Firebase config
console.log('Firebase Config Debug:', {
  apiKey: firebaseConfig.apiKey ? `${firebaseConfig.apiKey.substring(0, 10)}...` : 'missing',
  authDomain: firebaseConfig.authDomain || 'missing',
  projectId: firebaseConfig.projectId || 'missing',
  appId: firebaseConfig.appId ? `${firebaseConfig.appId.substring(0, 20)}...` : 'missing'
});

// Check if all required config is present
const requiredKeys = ['apiKey', 'authDomain', 'projectId', 'appId'];
const missingKeys = requiredKeys.filter(key => !firebaseConfig[key as keyof typeof firebaseConfig]);

if (missingKeys.length > 0) {
  console.error('Missing Firebase configuration:', missingKeys);
  console.error('Please check your .env file and ensure all VITE_FIREBASE_* variables are set');
}

const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
export const googleProvider = new GoogleAuthProvider();

// Set persistence to ensure auth state survives redirects
setPersistence(auth, browserLocalPersistence).catch((error) => {
  console.error('Failed to set Firebase persistence:', error);
});

// Add required scopes for Google provider
googleProvider.addScope('profile');
googleProvider.addScope('email');

console.log('🔧 [FIREBASE] Firebase initialized with persistence and scopes');

export default app;