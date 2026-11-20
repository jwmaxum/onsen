import type { MetadataRoute } from 'next';
import { siteOrigin } from '@/lib/metadata';

export const dynamic = 'force-dynamic';

export default function robots(): MetadataRoute.Robots {
  const origin = siteOrigin();
  if (!origin) return { rules: { userAgent: '*', disallow: '/' } };
  return { rules: { userAgent: '*', allow: '/', disallow: '/api/' }, sitemap: new URL('/sitemap.xml', origin).href };
}
