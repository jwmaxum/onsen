import { notFound } from 'next/navigation';
import { AccountPanel } from '@/components/account-panel';
import { Shell } from '@/components/shell';
import { isLocale } from '@/lib/catalog-query';
import { firebaseSiteOrigin } from '@/lib/firebase-site';
import { membershipText } from '@/lib/membership-copy';

export const dynamic = 'force-dynamic';
export const metadata = { robots: { index: false, follow: false } };

export default async function AccountPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const t = membershipText(locale);
  return <Shell locale={locale} hrefFor={(value) => `/${value}/onsen/account`}>
    <div className="container member-page member-narrow">
      <h1>{t('account')}</h1>
      <AccountPanel locale={locale} origin={firebaseSiteOrigin()} />
    </div>
  </Shell>;
}
