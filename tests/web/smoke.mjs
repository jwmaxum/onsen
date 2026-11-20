import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const load = createRequire(import.meta.url);
const { chromium } = load(process.env.ONSEN_PLAYWRIGHT_PATH ?? 'playwright');
const origin = new URL(process.env.ONSEN_WEB_TEST_URL ?? 'http://127.0.0.1:55440');
assert(['127.0.0.1', 'localhost', '[::1]'].includes(origin.hostname));
const screenshots = process.env.ONSEN_WEB_SCREENSHOTS;
if (screenshots) await mkdir(screenshots, { recursive: true });

const national = process.env.ONSEN_PHASE7_NATIONAL === '1';
const expanded = national || process.env.ONSEN_PHASE6_EXPANDED === '1';
const list = ['wakkanai-onsen-domu', ...(expanded ? ['wakkanai-minato-no-yu', 'rebun-usuyuki-no-yu', 'rishiri-fureai-onsen'] : []),
  'daiichi-takimotokan', ...(national ? ['hirakawa-fukuya', 'ikarigaseki-okariya-goten', 'sendai-seaside-kaijin-no-yu'] : []),
  'takegawara-onsen'];
const api = new URL('/api/v1/onsen-entries?locale=ko&limit=1', origin);
const slugs = [];
let cursor = null;
for (let page = 0; page < list.length; page++) {
  const url = new URL(api);
  if (cursor) url.searchParams.set('cursor', cursor);
  const response = await fetch(url);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.items.length, 1);
  slugs.push(body.items[0].slug);
  cursor = body.nextCursor;
  if (page === 0) {
    assert(cursor);
    const bad = new URL(url);
    bad.searchParams.set('cursor', cursor.slice(0, -1) + (cursor.endsWith('A') ? 'B' : 'A'));
    assert.equal((await fetch(bad)).status, 400);
    bad.searchParams.set('cursor', cursor);
    bad.searchParams.set('locale', 'ja');
    assert.equal((await fetch(bad)).status, 400);
  }
}
assert.deepEqual(slugs, list);
assert.equal(cursor, null);
console.log('PASS API latitude order, cursor pagination and tamper/reuse rejection');

const browser = await chromium.launch({ headless: true, executablePath: process.env.ONSEN_CHROME_PATH });
const errors = [];
try {
  for (const width of [360, 768, 1440]) {
    const page = await browser.newPage({ viewport: { width, height: 900 } });
    page.on('pageerror', (error) => errors.push(error.message));
    await page.goto(new URL('/ko/onsen', origin).href);
    assert.equal(await page.locator('.entry-card').count(), list.length);
    assert.deepEqual(await page.locator('.entry-list > li').evaluateAll((items) => items.map((item) => item.id.replace('entry-', ''))), list);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    if (width === 1440) {
      await page.keyboard.press('Tab');
      assert.equal(await page.evaluate(() => document.activeElement?.className), 'skip-link');
      if (screenshots) await page.screenshot({ path: join(screenshots, 'onsen-list-desktop.png'), fullPage: true });
    }
    await page.getByRole('link', { name: /다케가와라 온천/ }).filter({ has: page.getByRole('heading', { name: '다케가와라 온천' }) }).click();
    await page.getByRole('heading', { name: '다케가와라 온천', level: 1 }).waitFor();
    assert.equal(await page.locator('h1').textContent(), '다케가와라 온천');
    assert.equal(await page.locator('.analysis-card').count(), 3);
    assert.equal(await page.locator('.route-card').count(), 2);
    assert.equal(await page.getByText('가공 표기', { exact: true }).count(), 3);
    assert.equal(await page.locator('.analysis-card a[href$="bunseki_men.pdf"]').count(), 1);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    if (width === 360 && screenshots) await page.screenshot({ path: join(screenshots, 'onsen-detail-mobile.png'), fullPage: true });
    if (width === 768) {
      for (const [locale, label] of [['en', 'English'], ['zh-Hans', '简体中文'], ['ja', '日本語']]) {
        await page.getByRole('link', { name: label }).click();
        await page.waitForURL(`**/${locale}/onsen/facilities/takegawara-onsen**`);
        await page.locator(`html[lang="${locale}"] .analysis-card div[lang="${locale}"]`).first().waitFor();
        assert.equal(await page.locator(`.analysis-card div[lang="${locale}"]`).count(), 3);
        assert.equal(await page.locator('.route-card').count(), 2);
      }
    }
    await page.close();
  }
  const page = await browser.newPage({ viewport: { width: 900, height: 900 } });
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto(new URL('/ko/onsen?limit=1', origin).href);
  await page.waitForLoadState('networkidle');
  const noboribetsuIndex = list.indexOf('daiichi-takimotokan');
  for (const slug of list.slice(1, noboribetsuIndex + 1)) {
    await page.getByRole('button', { name: '더 보기' }).click();
    await page.locator(`#entry-${slug}`).waitFor();
  }
  assert.equal(await page.locator('.entry-card').count(), noboribetsuIndex + 1);
  await page.locator('#entry-daiichi-takimotokan a').click();
  await page.getByRole('heading', { name: '다이이치 타키모토칸', level: 1 }).waitFor();
  assert.equal(await page.locator('.route-card').count(), 1);
  assert.match(await page.locator('.back-link').getAttribute('href'), /cursor=.*#entry-daiichi-takimotokan$/);
  assert((await page.locator('.neighbor').first().getAttribute('href')).includes(list[noboribetsuIndex - 1]));
  assert((await page.locator('.neighbor-next').getAttribute('href')).includes(list[noboribetsuIndex + 1]));
  await page.getByRole('link', { name: 'English' }).click();
  await page.getByRole('heading', { name: 'Dai-ichi Takimotokan', level: 1 }).waitFor();
  assert.match(page.url(), /\/en\/onsen\/facilities\/daiichi-takimotokan/);
  assert.equal(await page.locator('html').getAttribute('lang'), 'en');
  assert.equal(await page.locator('h1').textContent(), 'Dai-ichi Takimotokan');
  await page.getByRole('link', { name: '简体中文' }).click();
  await page.getByRole('heading', { name: '第一泷本馆', level: 1 }).waitFor();
  assert.equal(await page.locator('h1').textContent(), '第一泷本馆');
  await page.getByRole('link', { name: '日本語' }).click();
  await page.getByRole('heading', { name: '第一滝本館', level: 1 }).waitFor();
  assert.equal(await page.locator('h1').textContent(), '第一滝本館');
  await page.getByRole('link', { name: '한국어' }).click();
  await page.getByRole('heading', { name: '다이이치 타키모토칸', level: 1 }).waitFor();
  assert.equal(await page.locator('h1').textContent(), '다이이치 타키모토칸');
  await page.goto(new URL('/ko/onsen/facilities/wakkanai-onsen-domu', origin).href);
  assert.equal(await page.locator('.route-card').count(), 1);
  assert.equal(await page.locator('.leg').count(), 3);
  await page.goto(new URL('/ko/onsen', origin).href);
  await page.getByLabel('지역', { exact: true }).selectOption('44');
  await page.getByRole('button', { name: '필터 적용' }).click();
  await page.waitForURL('**prefecture=44**');
  assert.equal(await page.locator('.entry-card').count(), 1);
  assert.equal(await page.locator('.entry-card h3').textContent(), '다케가와라 온천');
  if (expanded) {
    await page.setViewportSize({ width: 360, height: 900 });
    await page.getByRole('link', { name: '도도부현별 온천 조사 현황' }).click();
    await page.getByRole('heading', { name: '도도부현별 온천 조사 현황' }).waitFor();
    assert.equal(await page.locator('.coverage-table tbody tr').count(), 47);
    assert.match(await page.locator('[data-prefecture="01"]').innerText(), /표본 공개/);
    assert.match(await page.locator('[data-prefecture="02"]').innerText(), national ? /표본 공개/ : /미조사/);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth));
    await page.getByRole('link', { name: '온천지', exact: true }).click();
    await page.waitForURL('**kind=area');
    assert.equal(await page.locator('.coverage-table tbody tr').count(), 47);
    if (national) {
      await page.getByText('환경성 온천지 총계 · 2,839').waitFor();
      assert.match(await page.locator('[data-prefecture="02"]').innerText(), /명칭별 원장 미확보/);
      if (process.env.ONSEN_FY2024_ROSTERS === '1') {
        await page.getByText('원장 명칭 등록 · 241').waitFor();
        await page.getByText('원장 미확보 수 · 2,598').waitFor();
        assert.match(await page.locator('[data-prefecture="06"]').innerText(), /웹 재이용 조건 확인 대기/);
      }
    }
    await page.goto(new URL('/en/onsen/facilities/rebun-usuyuki-no-yu', origin).href);
    await page.getByRole('heading', { name: 'Rebun Island Onsen Usuyuki no Yu' }).waitFor();
    assert.equal(await page.locator('.source-links a[href$="1.geojson"]').count(), 1);
    console.log('PASS expanded Hokkaido data, coordinate attribution and 47-prefecture dashboard');
  }
  assert.deepEqual(errors, []);
  console.log('PASS responsive 360/768/1440, keyboard, filters, pagination, four locales, published analyses and three routes');
} finally { await browser.close(); }
