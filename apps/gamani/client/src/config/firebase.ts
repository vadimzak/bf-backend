import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider } from 'firebase/auth';

const firebaseConfig = {
  apiKey: 'AIzaSyBPBMw8Xiv8W_40fjL6p8pCaWwm_s5R_KU',
  authDomain: 'vzcreations.firebaseapp.com',
  projectId: 'vzcreations',
  storageBucket: 'vzcreations.firebasestorage.app',
  messagingSenderId: '799594505142',
  appId: '1:799594505142:web:80f0c81ba7f086aed81717'
};

console.log('🔧 [FIREBASE] Initializing with project:', firebaseConfig.projectId);

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize Auth
export const auth = getAuth(app);

// Initialize Google Auth Provider
export const googleProvider = new GoogleAuthProvider();
googleProvider.addScope('email');
googleProvider.addScope('profile');

// Configure provider for popup
googleProvider.setCustomParameters({
  prompt: 'select_account'
});

console.log('✅ [FIREBASE] Firebase initialized successfully');

export default app;