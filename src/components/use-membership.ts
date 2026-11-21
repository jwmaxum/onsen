'use client';

import { useEffect, useState } from 'react';
import { getAuth, onAuthStateChanged, type Auth, type User } from '@firebase/auth';
import { getDatabase, type Database } from '@firebase/database';
import { getFirebaseWebApp } from '@/lib/firebase-browser';

type MembershipSession = { auth?: Auth; database?: Database; user?: User | null; unavailable?: true };

export function useMembership(origin: string | null): MembershipSession {
  const [session, setSession] = useState<MembershipSession>({});
  useEffect(() => {
    if (!origin) return;
    let disposed = false;
    let unsubscribe: (() => void) | undefined;
    void Promise.resolve().then(() => {
      if (disposed) return;
      const app = getFirebaseWebApp();
      const auth = getAuth(app);
      const database = getDatabase(app, origin);
      unsubscribe = onAuthStateChanged(auth, (user) => setSession({ auth, database, user }),
        () => setSession({ unavailable: true }));
    }).catch(() => { if (!disposed) setSession({ unavailable: true }); });
    return () => { disposed = true; unsubscribe?.(); };
  }, [origin]);
  return origin ? session : { unavailable: true };
}
