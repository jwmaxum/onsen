import { notFound } from 'next/navigation';
import { AdminContent } from '@/components/admin-content';
import { Shell } from '@/components/shell';
import { isLocale } from '@/lib/catalog-query';
import { firebaseSiteOrigin } from '@/lib/firebase-site';
import { membershipText } from '@/lib/membership-copy';

export const dynamic = 'force-dynamic';
export const metadata = { robots: { index: false, follow: false } };

export default async function AdminPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return <Shell locale={locale} hrefFor={(value) => `/${value}/onsen/admin`}>
    <div className="container member-page">
      <h1>{membershipText(locale)('admin')}</h1>
      <AdminContent locale={locale} origin={firebaseSiteOrigin()} />
    </div>
  </Shell>;
}
