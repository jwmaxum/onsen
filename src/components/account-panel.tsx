'use client';

import { useEffect, useState, type FormEvent } from 'react';
import Link from 'next/link';
import { createUserWithEmailAndPassword, sendEmailVerification, signInWithEmailAndPassword, signOut } from '@firebase/auth';
import { get, ref, set } from '@firebase/database';
import type { Locale } from '@/lib/catalog-query';
import { membershipText } from '@/lib/membership-copy';
import { normalizeProfile, type Profile } from '@/lib/membership-types';
import { useMembership } from './use-membership';

export function AccountPanel({ locale, origin }: { locale: Locale; origin: string | null }) {
  const t = membershipText(locale);
  const { auth, database, unavailable, user } = useMembership(origin);
  const [signup, setSignup] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState<Parameters<typeof t>[0]>();
  const [account, setAccount] = useState<{ uid: string; profile: Profile | null; admin: boolean }>();
  const [verifiedUid, setVerifiedUid] = useState<string>();
  const current = user?.uid === account?.uid ? account : undefined;
  const verified = user && (user.emailVerified || user.uid === verifiedUid);

  useEffect(() => {
    if (!database || !user) return;
    let active = true;
    void Promise.all([get(ref(database, `profiles/${user.uid}`)), get(ref(database, `authorization/admins/${user.uid}`))])
      .then(([profile, admin]) => {
        if (active) setAccount((previous) => ({ uid: user.uid,
          profile: previous && previous.uid === user.uid && previous.profile ? previous.profile : profile.val(), admin: admin.val() === true }));
      })
      .catch(() => { if (active) setNotice('unavailable'); });
    return () => { active = false; };
  }, [database, user]);

  async function verifyEmail(action: 'send' | 'check') {
    if (!user || busy) return;
    setBusy(true);
    setNotice(undefined);
    try {
      if (action === 'send') {
        await sendEmailVerification(user);
        setNotice('verificationSent');
      } else {
        await user.reload();
        if (user.emailVerified) {
          await user.getIdToken(true);
          setVerifiedUid(user.uid);
          setNotice('verificationComplete');
        } else {
          setNotice('verificationPending');
        }
      }
    } catch {
      setNotice('unavailable');
    } finally {
      setBusy(false);
    }
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!auth || !database || busy) return;
    const fields = new FormData(event.currentTarget);
    const read = (key: string) => String(fields.get(key) ?? '');
    const profile = signup || user ? normalizeProfile(read('name'), read('phone')) : null;
    if ((signup || user) && !profile) { setNotice('badProfile'); return; }
    setBusy(true);
    setNotice(undefined);
    try {
      const email = read('email').trim();
      const password = read('password');
      const member = user ?? (signup
        ? await createUserWithEmailAndPassword(auth, email, password)
        : await signInWithEmailAndPassword(auth, email, password)).user;
      if (profile) {
        await set(ref(database, `profiles/${member.uid}`), profile);
        const admin = await get(ref(database, `authorization/admins/${member.uid}`));
        setAccount({ uid: member.uid, profile, admin: admin.val() === true });
        setNotice('saved');
      }
    } catch {
      setNotice(auth.currentUser ? 'unavailable' : signup ? 'badSignup' : 'badLogin');
    } finally {
      setBusy(false);
    }
  }

  if (unavailable) return <p role="status">{t('unavailable')}</p>;
  if (user === undefined) return <p role="status">{t('loading')}</p>;
  return <div className="member-card">
    {notice && <p role="status" className="member-notice">{t(notice)}</p>}
    {!user && <div className="member-actions">
      <button className={signup ? 'button button-outline' : 'button'} aria-pressed={!signup} type="button"
        onClick={() => { setSignup(false); setNotice(undefined); }}>{t('signIn')}</button>
      <button className={signup ? 'button' : 'button button-outline'} aria-pressed={signup} type="button"
        onClick={() => { setSignup(true); setNotice(undefined); }}>{t('signUp')}</button>
    </div>}
    {user && <div className="member-actions">
      <span>{user.email}</span>
      <button className="button button-outline" disabled={busy} type="button" onClick={() => {
        setNotice(undefined);
        if (auth) void signOut(auth).then(() => {
          setSignup(false); setAccount(undefined); setVerifiedUid(undefined);
        }).catch(() => setNotice('unavailable'));
      }}>{t('signOut')}</button>
      {current?.admin && verified && <Link className="button" href={`/${locale}/onsen/admin`}>{t('admin')}</Link>}
    </div>}
    {user && !verified && <div className="member-form">
      <p>{t(current?.admin ? 'verificationPending' : 'verifyEmail')}</p>
      <div className="member-actions">
        <button className="button" type="button" disabled={busy} onClick={() => void verifyEmail('send')}>
          {t('sendVerification')}
        </button>
        <button className="button button-outline" type="button" disabled={busy} onClick={() => void verifyEmail('check')}>
          {t('checkVerification')}
        </button>
      </div>
    </div>}
    {(!user || current || notice === 'unavailable') && <form className="member-form" onSubmit={submit}
      key={user ? `${user.uid}-${Boolean(current?.profile)}` : String(signup)}>
      {!user && <>
        <label>{t('email')}<input name="email" type="email" autoComplete="username" required maxLength={254} /></label>
        <label>{t('password')}<input name="password" type="password" autoComplete={signup ? 'new-password' : 'current-password'}
          required minLength={signup ? 6 : undefined} maxLength={128} /></label>
      </>}
      {(user || signup) && <>
        {user && !current?.profile && <p>{t('profilePending')}</p>}
        <label>{t('name')}<input name="name" autoComplete="name" defaultValue={current?.profile?.name} required maxLength={80} /></label>
        <label>{t('phone')}<input name="phone" type="tel" autoComplete="tel" defaultValue={current?.profile?.phone}
          required maxLength={32} aria-describedby="profile-privacy" /></label>
        <p id="profile-privacy">{t('profileNotice')}</p>
      </>}
      <button className="button" type="submit" disabled={busy}>{t(user ? 'save' : signup ? 'signUp' : 'signIn')}</button>
    </form>}
  </div>;
}
