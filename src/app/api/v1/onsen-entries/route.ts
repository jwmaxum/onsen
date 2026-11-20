import { NextResponse } from 'next/server';
import { getCatalogPage } from '@/lib/catalog';
import { CatalogError, parseCatalogQuery } from '@/lib/catalog-query';

const headers = { 'Cache-Control': 'no-store' };

export async function GET(request: Request) {
  try {
    const query = parseCatalogQuery(new URL(request.url).searchParams);
    return NextResponse.json(await getCatalogPage(query), { headers });
  } catch (error) {
    if (error instanceof CatalogError) return NextResponse.json({ error: error.code }, { status: error.status, headers });
    return NextResponse.json({ error: 'data_unavailable' }, { status: 503, headers });
  }
}
