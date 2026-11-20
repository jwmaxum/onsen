import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { join, resolve } from 'node:path';

const [toolsDirectory, option] = process.argv.slice(2);
if (!toolsDirectory || (option && option !== '--write-types')) {
  throw new Error('Usage: node scripts/check-db.mjs <tools-directory> [--write-types]');
}

const load = createRequire(join(resolve(toolsDirectory), 'package.json'));
const { PGlite } = load('@electric-sql/pglite');
const { postgis } = load('@electric-sql/pglite-postgis');
const { createNodeHost, findLanguage, introspect } = load('@supabase/typegen');
const migrations = new URL('../supabase/migrations/', import.meta.url);
const seed = new URL('../supabase/seed.sql', import.meta.url);
const contract = new URL('../tests/db/phase1.sql', import.meta.url);
const typeFile = new URL('../src/types/database.types.ts', import.meta.url);
const migrationFiles = (await readdir(migrations)).filter((file) => file.endsWith('.sql')).sort();

for (const run of [1, 2]) {
  const db = new PGlite({ extensions: { postgis } });
  try {
    await db.exec(`
      create role anon nologin;
      create role authenticated nologin;
      create role service_role nologin bypassrls;
    `);
    for (const file of migrationFiles) {
      await db.exec(await readFile(new URL(file, migrations), 'utf8'));
    }
    await db.exec(await readFile(seed, 'utf8'));
    await db.exec(await readFile(contract, 'utf8'));
    const { rows: [versions] } = await db.query(`
      select current_setting('server_version') as postgres, extversion as postgis
      from pg_extension where extname = 'postgis'
    `);
    console.log(`PASS ${run}/2: migrations, seed and contract (${versions.postgres} / PostGIS ${versions.postgis})`);

    if (run === 2) {
      const metadata = await introspect(db, { includedSchemas: ['api'] });
      const generator = findLanguage('typescript');
      const host = createNodeHost({ cwd: process.cwd(), env: {} });
      const generated = await generator.generate(metadata, { 'default-schema': 'api' }, host);
      if (option === '--write-types') {
        await mkdir(new URL('./', typeFile), { recursive: true });
        await writeFile(typeFile, generated, 'utf8');
      } else if ((await readFile(typeFile, 'utf8')).replaceAll('\r\n', '\n') !== generated) {
        throw new Error('The checked-in API types differ from the database schema');
      }
      console.log('PASS: Supabase API type generation');
    }
  } finally {
    await db.close();
  }
}
