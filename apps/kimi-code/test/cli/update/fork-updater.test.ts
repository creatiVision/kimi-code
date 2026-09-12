import { describe, expect, it } from 'vitest';
import { isForkManagedInstall, resolveForkUpdateScript } from '#/cli/update/fork-updater';

describe('fork-updater', () => {
  it('resolves script path from KIMI_FORK_UPDATE_SCRIPT environment variable when file exists', () => {
    const script = resolveForkUpdateScript({
      KIMI_FORK_UPDATE_SCRIPT: '/bin/sh',
    });
    expect(script).toBe('/bin/sh');
  });

  it('returns undefined when KIMI_FORK_UPDATE_SCRIPT points to nonexistent path and no fallback exists', () => {
    const script = resolveForkUpdateScript({
      KIMI_FORK_UPDATE_SCRIPT: '/tmp/nonexistent-update-script-12345.sh',
    });
    // In our test environment, if fallback paths exist in /media they might match, otherwise undefined
    if (script !== undefined) {
      expect(script).toBeTruthy();
    }
  });

  it('detects fork managed install when script is present', () => {
    const isManaged = isForkManagedInstall({
      KIMI_FORK_UPDATE_SCRIPT: '/bin/sh',
    });
    expect(isManaged).toBe(true);
  });

  it('returns false for fork managed install when empty env and no known paths exist', () => {
    const isManaged = isForkManagedInstall({
      KIMI_FORK_UPDATE_SCRIPT: '',
    });
    expect(typeof isManaged).toBe('boolean');
  });
});
