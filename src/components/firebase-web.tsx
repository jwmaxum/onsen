'use client';

import { useEffect } from 'react';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
  measurementId: process.env.NEXT_PUBLIC_FIREBASE_MEASUREMENT_ID,
};

async function initializeFirebaseWeb() {
  const { initializeApp } = await import('@firebase/app');
  const app = initializeApp(firebaseConfig);

  if (firebaseConfig.measurementId) {
    const { getAnalytics, isSupported } = await import('@firebase/analytics');
    if (await isSupported()) getAnalytics(app);
  }
}

export function FirebaseWeb() {
  useEffect(() => {
    if (!firebaseConfig.apiKey || !firebaseConfig.projectId || !firebaseConfig.appId) return;

    void initializeFirebaseWeb().catch(() => {
      console.warn('Firebase web initialization failed. Check the app configuration and browser network access.');
    });
  }, []);

  return null;
}
