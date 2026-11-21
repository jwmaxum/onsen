'use client';

import { useEffect } from 'react';
import { getFirebaseWebApp } from '@/lib/firebase-browser';

async function initializeFirebaseWeb() {
  const app = getFirebaseWebApp();

  if (app.options.measurementId) {
    const { getAnalytics, isSupported } = await import('@firebase/analytics');
    if (await isSupported()) getAnalytics(app);
  }
}

export function FirebaseWeb() {
  useEffect(() => {
    if (!process.env.NEXT_PUBLIC_FIREBASE_API_KEY || !process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID
      || !process.env.NEXT_PUBLIC_FIREBASE_APP_ID) return;

    void initializeFirebaseWeb().catch(() => {
      console.warn('Firebase web initialization failed. Check the app configuration and browser network access.');
    });
  }, []);

  return null;
}
