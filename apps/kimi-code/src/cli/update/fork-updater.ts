import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Known locations where the custom multi-host fork update script resides.
 */
const KNOWN_FORK_UPDATE_SCRIPT_PATHS = [
  '/media/xchg/ai-tools-data/kimi-skills/update-kimi-code/bin/kimi-fork-update.sh',
  '/media/xchg/ai-tools-data/skillshub/update-kimi-code/bin/kimi-fork-update.sh',
  '/media/sdc2-2tb-work-privat-xchg/00_Work/002_cv-projects/cv_ai_kimi-code-cli-fork/scripts/kimi-fork-update.sh',
  '/media/work-data/002_cv-projects/cv_ai_kimi-code-cli-fork/scripts/kimi-fork-update.sh',
];

/**
 * Detect whether this installation is managed by our custom fork build & deploy
 * pipeline. Resolves the absolute path to `kimi-fork-update.sh` if present.
 *
 * Precedence:
 * 1. `KIMI_FORK_UPDATE_SCRIPT` environment variable (if set and file exists)
 * 2. Shared xchg / skillshub paths
 * 3. Local repository checkout relative scripts
 */
export function resolveForkUpdateScript(env: NodeJS.ProcessEnv = process.env): string | undefined {
  const envPath = env['KIMI_FORK_UPDATE_SCRIPT']?.trim();
  if (envPath && envPath.length > 0 && existsSync(envPath)) {
    return resolve(envPath);
  }

  for (const candidate of KNOWN_FORK_UPDATE_SCRIPT_PATHS) {
    if (existsSync(candidate)) {
      return candidate;
    }
  }

  return undefined;
}

/**
 * Returns true if a fork update script was detected on the current host.
 */
export function isForkManagedInstall(env: NodeJS.ProcessEnv = process.env): boolean {
  return resolveForkUpdateScript(env) !== undefined;
}
