import 'server-only';

export function firebaseSiteOrigin() {
  const configured = process.env.ONSEN_FIREBASE_DATABASE_URL;
  if (!configured) return null;
  try {
    const url = new URL(configured);
    if (url.protocol === 'https:' && url.href === `${url.origin}/` && !url.port
      && /^[a-z0-9-]+\.(?:firebaseio\.com|[a-z0-9-]+\.firebasedatabase\.app)$/.test(url.hostname)) {
      return url.origin;
    }
  } catch {
    return null;
  }
  return null;
}
