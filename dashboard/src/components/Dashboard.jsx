import TaskCard from './TaskCard';
import { timeAgo } from '../utils.js';

export default function Dashboard({ sessions, tasks, error, lastRefresh }) {
  // Merge sessions and tasks by paneId
  const items = sessions.map((s) => {
    const task = tasks.find((t) => t.paneId === s.paneId);
    return { ...s, task };
  });

  // Count active
  const aliveCount = sessions.filter((s) => s.status === 'alive').length;
  const taskRunning = tasks.filter((t) => t.overallStatus === 'in_progress').length;

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
