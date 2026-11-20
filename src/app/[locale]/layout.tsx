import type { ReactNode } from 'react';
import { notFound } from 'next/navigation';
import { FirebaseWeb } from '@/components/firebase-web';
import { isLocale } from '@/lib/catalog-query';
import { text } from '@/lib/i18n';
import '../globals.css';

export default async function LocaleLayout({ children, params }: { children: ReactNode; params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const t = text(locale);
  return (
    <html lang={locale}>
      <body>
        <a className="skip-link" href="#main">{t('skip')}</a>
        {children}
        <FirebaseWeb />
      </body>
    </html>
  );
}
