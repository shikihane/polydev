import TaskCard from './TaskCard';
import { timeAgo } from '../utils.js';

export default function Dashboard({ sessions, tasks, error, lastRefresh, config }) {
  // Merge sessions and tasks by paneId
  const matchedTaskPaneIds = new Set();
  const sessionItems = sessions.map((s) => {
    const task = tasks.find((t) => t.paneId === s.paneId);
    if (task) matchedTaskPaneIds.add(task.paneId);
    return { ...s, task };
  });

  // Tasks whose pane is gone (completed/failed) show as orphaned
  const orphanedItems = tasks
    .filter((t) => !matchedTaskPaneIds.has(t.paneId))
    .map((t) => ({
      sessionId: `orphan:${t.paneId}`,
      type: 'wo',
      name: t.branch || t.worktree || 'Unknown',
      status: 'ended',
      cwd: t.worktree || '',
      paneId: t.paneId,
      task: t,
      orphaned: true,
    }));

  const items = [...sessionItems, ...orphanedItems];

  // Count active — only tasks with a live session count as running
  const aliveCount = sessions.filter((s) => s.status === 'alive').length;
  const taskRunning = tasks.filter(
    (t) => t.overallStatus === 'in_progress' && matchedTaskPaneIds.has(t.paneId)
  ).length;
  const endedCount = orphanedItems.length;

  return (
    <div className="dashboard">
      <div className="dashboard-header">
        <h1>Polydev Dashboard</h1>
        <div className="status-bar">
          <span>
            <span className={`status-dot ${error ? 'error' : 'live'}`} />
            {error ? 'Disconnected' : 'Live'}
          </span>
          {lastRefresh && <span>Updated {timeAgo(lastRefresh.toISOString())}</span>}
        </div>
      </div>

      {config?.projectRoot && (
        <div className="project-root">Project: {config.projectRoot}</div>
      )}

      {error && <div className="error-banner">API Error: {error}</div>}

      <div className="summary">
        <div className="summary-item">
          <strong>{aliveCount}</strong>
          Active Sessions
        </div>
        <div className="summary-item">
          <strong>{taskRunning}</strong>
          Running Tasks
        </div>
        <div className="summary-item">
          <strong>{sessions.length}</strong>
          Total Sessions
        </div>
        {endedCount > 0 && (
          <div className="summary-item">
            <strong>{endedCount}</strong>
            Ended Tasks
          </div>
        )}
      </div>

      <div className="card-list">
        {items.length === 0 && (
          <div className="summary-item" style={{ textAlign: 'center', color: '#8b949e' }}>
            No active sessions. Start a polydev task to see it here.
          </div>
        )}
        {items.map((item) => (
          <TaskCard key={item.paneId || item.sessionId} item={item} />
        ))}
      </div>
    </div>
  );
}
