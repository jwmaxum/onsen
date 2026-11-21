'use client';

import Link from 'next/link';
import { useEffect, useState, type FormEvent } from 'react';
import { get, onValue, ref, runTransaction } from '@firebase/database';
import { isLocale, locales, localeLabels, type Locale } from '@/lib/catalog-query';
import { membershipText } from '@/lib/membership-copy';
import { articleRows, type Article, type ArticleStore } from '@/lib/membership-types';
import { useMembership } from './use-membership';

export function AdminContent({ locale, origin }: { locale: Locale; origin: string | null }) {
  const t = membershipText(locale);
  const { database, user, unavailable } = useMembership(origin);
  const [membership, setMembership] = useState<{ uid: string; allowed: boolean; rows?: [string, Article][] }>();
  const [selection, setSelection] = useState<[string, Article]>();
  const [formRevision, setFormRevision] = useState(0);
  const [notice, setNotice] = useState<Parameters<typeof t>[0]>();
  const [busy, setBusy] = useState(false);
  const active = membership?.uid === user?.uid ? membership : undefined;

  useEffect(() => {
    if (!database || !user?.emailVerified) return;
    let cancelled = false;
    let stop: (() => void) | undefined;
    const uid = user.uid;
    void get(ref(database, `authorization/admins/${uid}`)).then((result) => {
      if (cancelled) return;
      if (result.val() !== true) { setMembership({ uid, allowed: false }); return; }
      stop = onValue(ref(database, 'site_content'), (snapshot) => {
        if (!cancelled) setMembership({ uid, allowed: true, rows: articleRows(snapshot.child('drafts').val()) });
      }, () => { if (!cancelled) setMembership({ uid, allowed: false }); });
    }).catch(() => { if (!cancelled) setNotice('unavailable'); });
    return () => { cancelled = true; stop?.(); };
  }, [database, user]);

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!database || !active?.allowed || busy) return;
    const fields = new FormData(event.currentTarget);
    const language = String(fields.get('locale'));
    const title = String(fields.get('title') ?? '').trim();
    const body = String(fields.get('body') ?? '').trim();
    if (!isLocale(language) || !title || title.length > 100 || !body || body.length > 8000) return;
    const id = selection?.[0] ?? crypto.randomUUID();
    const entry: Article = { locale: language, title, body, published: fields.get('published') === 'on',
      updatedAt: Date.now(), revision: crypto.randomUUID() };
    setNotice(undefined);
    setBusy(true);
    try {
      const result = await runTransaction(ref(database, 'site_content'), (stored: ArticleStore | null) => {
        const drafts = { ...stored?.drafts };
        const published = { ...stored?.public };
        const old = drafts[id];
        if (selection && (!old || old.revision !== selection[1].revision)) return;
        drafts[id] = entry;
        if (old?.published) {
          const oldLanguage = { ...published[old.locale] };
          delete oldLanguage[id];
          published[old.locale] = oldLanguage;
        }
        if (entry.published) published[language] = { ...published[language], [id]: entry };
        return { drafts, public: published } satisfies ArticleStore;
      }, { applyLocally: false });
      if (result.committed) setSelection([id, entry]);
      setNotice(result.committed ? 'saved' : 'conflict');
    } catch {
      setNotice('unavailable');
    } finally {
      setBusy(false);
    }
  }

  if (unavailable) return <p role="status">{t('unavailable')}</p>;
  if (user === null || (user && !user.emailVerified) || active?.allowed === false) return <div className="member-card">
    <p role="status">{t('denied')}</p><Link className="button" href={`/${locale}/onsen/account`}>{t('signIn')}</Link>
  </div>;
  if (!active?.allowed) return <p role="status">{t(notice ?? 'loading')}</p>;
  return <div className="member-admin">
    <section className="member-card" aria-label={t('articles')}>
      <button type="button" className="button button-outline" disabled={busy} onClick={() => {
        setSelection(undefined); setFormRevision((value) => value + 1); setNotice(undefined);
      }}>{t('newArticle')}</button>
      {active.rows?.length ? <ul className="member-article-list">{active.rows.map(([id, entry]) => <li key={id}>
        <span><strong>{entry.title}</strong><small>{localeLabels[entry.locale]} · {t(entry.published ? 'published' : 'draft')}</small></span>
        <button type="button" className="button button-outline" disabled={busy} onClick={() => {
          setSelection([id, entry]); setFormRevision((value) => value + 1); setNotice(undefined);
        }}>{t('edit')}</button>
      </li>)}</ul> : <p>{t('empty')}</p>}
    </section>
    <section className="member-card">
      {notice && <p role="status" className="member-notice">{t(notice)}</p>}
      <form key={`${user?.uid}-${formRevision}`} className="member-form" onSubmit={save}>
        <label>{t('locale')}<select name="locale" defaultValue={selection?.[1].locale ?? locale}>
          {locales.map((language) => <option key={language} value={language}>{localeLabels[language]}</option>)}
        </select></label>
        <label>{t('title')}<input name="title" required maxLength={100} defaultValue={selection?.[1].title} /></label>
        <label>{t('body')}<textarea name="body" required maxLength={8000} rows={10} defaultValue={selection?.[1].body} /></label>
        <label className="member-checkbox"><input name="published" type="checkbox" defaultChecked={selection?.[1].published} />{t('publish')}</label>
        <button className="button" type="submit" disabled={busy}>{t('save')}</button>
      </form>
    </section>
  </div>;
}
