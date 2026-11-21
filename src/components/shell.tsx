import Link from 'next/link';
import { Waves } from 'lucide-react';
import type { ReactNode } from 'react';
import { locales, type Locale } from '@/lib/catalog-query';
import { localeLabels, text } from '@/lib/i18n';
import { membershipText } from '@/lib/membership-copy';

export function Shell({ locale, hrefFor, children }: {
  locale: Locale;
  hrefFor: (value: Locale) => string;
  children: ReactNode;
}) {
  const t = text(locale);
  const member = membershipText(locale);
  return <>
    <header className="site-header">
      <div className="container header-inner">
        <Link className="brand" href={`/${locale}/onsen`}>
          <span className="brand-icon"><Waves size={21} aria-hidden="true" /></span>
          <span>{t('brand')}<span className="brand-caption" lang="en">ONSEN ATLAS</span></span>
        </Link>
        <div className="header-navigation"><nav aria-label={t('language')} className="language-nav">
          {locales.map((value) => <Link key={value} href={hrefFor(value)} lang={value} hrefLang={value}
            aria-current={value === locale ? 'page' : undefined}>{localeLabels[value]}</Link>)}
        </nav><div className="member-links">
          <Link href={`/${locale}/onsen/news`}>{member('articles')}</Link>
          <Link href={`/${locale}/onsen/account`}>{member('account')}</Link>
        </div></div>
      </div>
    </header>
    <main id="main">{children}</main>
    <footer className="site-footer"><div className="container footer-inner"><strong>{t('brand')}</strong><p>{t('footer')}</p></div></footer>
  </>;
}
