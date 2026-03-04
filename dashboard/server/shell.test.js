// server/shell.test.js
import { describe, it, expect } from 'vitest';
import { parseSessionsToon, parseTaskToon } from './shell.js';

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
