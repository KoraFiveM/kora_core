// usage: node apply.js <db> <sqlDir>  (env: MARIADB, KORA_SQL_DIR, MAX_VERSION)
// Emulates kora_sql's Migrator: its splitStatements, its retry-safety gate, per-statement exec.
const { splitStatements } = require((process.env.KORA_SQL_DIR || '../kora_sql') + '/server/js/migrate.js');
const fs = require('fs'), cp = require('child_process');
const [db, dir] = process.argv.slice(2);
const files = fs.readdirSync(dir).filter(f => /^\d{3}_.*\.sql$/.test(f)).sort()
  .filter(f => !f.startsWith('003_')) // generated columns are opt-in, off by default
  .filter(f => !process.env.MAX_VERSION || parseInt(f, 10) <= parseInt(process.env.MAX_VERSION, 10));
const mariadb = (process.env.MARIADB || 'sudo mariadb').split(' ');
for (const f of files) {
  const sql = fs.readFileSync(`${dir}/${f}`, 'utf8');
  const statements = splitStatements(sql).filter(s => s.trim());
  for (const stmt of statements) {
    const w = stmt.replace(/^\s*(?:--[^\n]*\n\s*)*/g, '');
    const safeCreate = /^CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\b/i.test(w);
    const adds = w.match(/\bADD\b/gi) || [];
    const safeAdds = w.match(/\bADD\s+(?:COLUMN|(?:UNIQUE\s+)?INDEX)\s+IF\s+NOT\s+EXISTS\b/gi) || [];
    const drops = w.match(/\bDROP\b/gi) || [];
    const safeDrops = w.match(/\bDROP\s+INDEX\s+IF\s+EXISTS\b/gi) || [];
    const safeAlter = /^ALTER\s+TABLE\b/i.test(w) && adds.length > 0 && adds.length === safeAdds.length && drops.length === safeDrops.length;
    if (!safeCreate && !safeAlter) { console.log(`RUNNER REJECTS ${f}: ${w.slice(0,70).replace(/\s+/g,' ')}...`); process.exit(2); }
  }
  for (const stmt of statements) {
    const r = cp.spawnSync(mariadb[0], [...mariadb.slice(1), db], { input: stmt, encoding: 'utf8' });
    if (r.status) { console.log(`FAIL ${f}: ${r.stderr}`); process.exit(3); }
  }
  console.log('applied', f);
}
