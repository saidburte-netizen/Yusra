import fs from 'node:fs';
import path from 'node:path';
import type { FullConfig } from '@playwright/test';

/**
 * Fail fast, and with a useful message, when the stack was not bootstrapped.
 * No credentials are read or written here: they stay in the process env that
 * bootstrap/start-stack.sh exports from `supabase status`.
 */
async function globalSetup(config: FullConfig) {
  const required = [
    'UAT_SUPABASE_URL',
    'UAT_ANON_KEY',
    'UAT_SERVICE_KEY',
    'UAT_RUN_ID',
    'UAT_BRANCH_A_ID',
    'UAT_BRANCH_B_ID',
  ];
  const missing = required.filter((name) => !process.env[name]);
  if (missing.length) {
    throw new Error(
      `UAT stack is not bootstrapped. Missing environment variables: ${missing.join(', ')}. ` +
        'Run: bash tool/uat/bootstrap/start-stack.sh (see tool/uat/README.md).',
    );
  }

  const response = await fetch(`${process.env.UAT_SUPABASE_URL}/rest/v1/`, {
    headers: {
      apikey: process.env.UAT_ANON_KEY!,
      Authorization: `Bearer ${process.env.UAT_ANON_KEY!}`,
    },
  });
  if (!response.ok) {
    throw new Error(
      `PostgREST at ${process.env.UAT_SUPABASE_URL}/rest/v1 returned HTTP ${response.status}. ` +
        'The local Supabase stack is not ready.',
    );
  }

  const artifacts = path.resolve(__dirname, '..', 'artifacts');
  fs.mkdirSync(path.join(artifacts, 'screenshots'), { recursive: true });
  fs.mkdirSync(path.join(artifacts, 'videos'), { recursive: true });
  fs.writeFileSync(
    path.join(artifacts, 'run.json'),
    JSON.stringify(
      {
        runId: process.env.UAT_RUN_ID,
        webUrl: process.env.UAT_WEB_URL ?? 'http://127.0.0.1:4173',
        supabaseUrl: process.env.UAT_SUPABASE_URL,
        branchA: process.env.UAT_BRANCH_A_ID,
        branchB: process.env.UAT_BRANCH_B_ID,
        generatedAt: new Date().toISOString(),
        // Deliberately no keys: credentials are never persisted as evidence.
      },
      null,
      2,
    ),
  );

  void config;
}

export default globalSetup;
