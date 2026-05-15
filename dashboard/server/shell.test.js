// server/shell.test.js
import { describe, it, expect } from 'vitest';
import {
  parseSessionsToon,
  parseTaskToon,
  parseWezTermSessions,
  isValidPaneId,
  resolveProjectRoot,
  worktreesDirForProject,
  resolveScriptsPath,
} from './shell.js';

describe('parseSessionsToon', () => {
  it('parses single TOON line', () => {
    const input = 'session_id=wo:myproject:feature.0,status=alive,cwd=/c/Users/test/project,pane_id=5';
    const result = parseSessionsToon(input);
    expect(result).toEqual([{
      sessionId: 'wo:myproject:feature.0',
      type: 'wo',
      name: 'feature',
      status: 'alive',
      cwd: '/c/Users/test/project',
      paneId: '5',
    }]);
  });

  it('parses multiple lines', () => {
    const input = [
      'session_id=wo:proj:auth.0,status=alive,cwd=/tmp/a,pane_id=5',
      'session_id=bg-proj:build.0,status=alive,cwd=/tmp/b,pane_id=7',
    ].join('\n');
    const result = parseSessionsToon(input);
    expect(result).toHaveLength(2);
    expect(result[0].type).toBe('wo');
    expect(result[1].type).toBe('bg');
  });

  it('handles empty input', () => {
    expect(parseSessionsToon('')).toEqual([]);
    expect(parseSessionsToon('(No sessions found)')).toEqual([]);
  });

  it('preserves tmux pane_id format', () => {
    const input = 'session_id=wo:proj:main.0,status=alive,cwd=/home/user/proj,pane_id=%3';
    const result = parseSessionsToon(input);
    expect(result[0].paneId).toBe('%3');
  });
});

describe('parseWezTermSessions', () => {
  it('converts WezTerm panes to dashboard sessions', () => {
    const raw = JSON.stringify([
      {
        pane_id: 5,
        workspace: 'polydev',
        tab_title: 'feature-auth [5]',
        cwd: 'file://E:/repo/.worktrees/auth',
      },
      {
        pane_id: 7,
        workspace: 'ag-polydev',
        tab_title: 'research [7]',
        cwd: 'file://E:/repo',
      },
    ]);

    expect(parseWezTermSessions(raw)).toEqual([
      {
        sessionId: '5',
        type: 'wo',
        name: 'feature-auth',
        status: 'alive',
        cwd: 'E:/repo/.worktrees/auth',
        paneId: '5',
      },
      {
        sessionId: '7',
        type: 'ag',
        name: 'research',
        status: 'alive',
        cwd: 'E:/repo',
        paneId: '7',
      },
    ]);
  });

  it('handles empty or malformed WezTerm JSON safely', () => {
    expect(parseWezTermSessions('')).toEqual([]);
    expect(parseWezTermSessions('not json')).toEqual([]);
  });
});

describe('parseTaskToon', () => {
  it('parses task.toon content', () => {
    const content = `meta{worktree,branch,pane_id,created}:
  /path/to/wt,feature-auth,5,2026-03-04T09:00:00Z

verification{level,fallback,commands}:
  L2,L1,

overall_status: in_progress
agent_status: active
blocking_reason:
last_update: 2026-03-04T10:30:00Z`;

    const result = parseTaskToon(content);
    expect(result).toEqual({
      worktree: '/path/to/wt',
      branch: 'feature-auth',
      paneId: '5',
      created: '2026-03-04T09:00:00Z',
      overallStatus: 'in_progress',
      agentStatus: 'active',
      blockingReason: '',
      lastUpdate: '2026-03-04T10:30:00Z',
    });
  });
});

describe('isValidPaneId', () => {
  it('accepts numeric pane ids', () => {
    expect(isValidPaneId('5')).toBe(true);
    expect(isValidPaneId('123')).toBe(true);
  });

  it('accepts tmux percent-prefixed pane ids', () => {
    expect(isValidPaneId('%0')).toBe(true);
    expect(isValidPaneId('%42')).toBe(true);
  });

  it('accepts tmux session:window.pane format', () => {
    expect(isValidPaneId('polydev:1.0')).toBe(true);
    expect(isValidPaneId('my-session:0.1')).toBe(true);
  });

  it('rejects shell metacharacters', () => {
    expect(isValidPaneId('5; rm -rf /')).toBe(false);
    expect(isValidPaneId('$(whoami)')).toBe(false);
    expect(isValidPaneId('`id`')).toBe(false);
    expect(isValidPaneId('5 && echo pwned')).toBe(false);
    expect(isValidPaneId('5|cat /etc/passwd')).toBe(false);
  });

  it('rejects non-string input', () => {
    expect(isValidPaneId(null)).toBe(false);
    expect(isValidPaneId(undefined)).toBe(false);
    expect(isValidPaneId(42)).toBe(false);
  });

  it('rejects empty string', () => {
    expect(isValidPaneId('')).toBe(false);
  });
});

describe('resolveProjectRoot', () => {
  it('uses explicit query/root value first', () => {
    expect(resolveProjectRoot('E:/repo', { env: {}, cwd: 'E:/skill/dashboard' })).toBe('E:/repo');
  });

  it('uses POLYDEV_PROJECT_ROOT when explicit value is absent', () => {
    expect(resolveProjectRoot('', {
      env: { POLYDEV_PROJECT_ROOT: '/home/me/project' },
      cwd: '/home/me/.claude/skills/polydev/dashboard',
    })).toBe('/home/me/project');
  });

  it('falls back to cwd only when no explicit project root exists', () => {
    expect(resolveProjectRoot('', { env: {}, cwd: '/tmp/project' })).toBe('/tmp/project');
  });
});

describe('worktreesDirForProject', () => {
  it('resolves .worktrees below the project root', () => {
    expect(worktreesDirForProject('E:/repo').replace(/\\/g, '/')).toBe('E:/repo/.worktrees');
  });
});

describe('resolveScriptsPath', () => {
  it('defaults to the dashboard sibling scripts directory', () => {
    const scripts = resolveScriptsPath('E:/skill/dashboard/server');
    expect(scripts.replace(/\\/g, '/')).toBe('E:/skill/scripts');
  });

  it('allows an explicit scripts root for tests and advanced callers', () => {
    expect(resolveScriptsPath('ignored', 'E:/custom/scripts')).toBe('E:/custom/scripts');
  });
});
