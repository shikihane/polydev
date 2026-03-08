import { useState } from 'react';
import TerminalView from './TerminalView';
import { timeAgo } from '../utils.js';

export default function TaskCard({ item }) {
  const [expanded, setExpanded] = useState(false);
  const [refreshInterval, setRefreshInterval] = useState(3);

  const { type, name, paneId, status, task, orphaned } = item;

  const branch = task?.branch || name;
  const created = task?.created || '';

  const dotClass = orphaned
    ? 'ended'
    : task
      ? (task.agentStatus || 'pending')
      : (status === 'alive' ? 'active' : 'dead');

  const statusText = orphaned
    ? (task?.overallStatus === 'completed' ? 'completed' : 'ended (pane lost)')
    : task
      ? `${task.overallStatus || ''} / ${task.agentStatus || status}`
      : status;

  const canShowTerminal = !orphaned && paneId;

  return (
    <div className={`task-card${orphaned ? ' orphaned' : ''}`}>
      <div className="card-header" onClick={() => canShowTerminal && setExpanded(!expanded)}>
        <div className="card-header-left">
          <span className={`card-type ${orphaned ? 'ended' : type}`}>{type}</span>
          <span className="card-name">{branch || name}</span>
          {orphaned && <span className="card-type ended">ended</span>}
        </div>
        {canShowTerminal && (
          <button className="toggle-btn">
            {expanded ? '\u25B2 Hide Terminal' : '\u25BC Show Terminal'}
          </button>
        )}
      </div>

      <div className="card-details">
        <div className="card-status">
          <span className={`dot ${dotClass}`} />
          {statusText}
        </div>
        {created && <span>Since: {timeAgo(created)}</span>}
        {task?.blockingReason && (
          <span style={{ color: '#f85149' }}>Blocked: {task.blockingReason}</span>
        )}
      </div>

      {expanded && canShowTerminal && (
        <>
          <div className="terminal-toolbar">
            <span>Pane #{paneId}</span>
            <label>
              Refresh:&nbsp;
              <select
                className="interval-select"
                value={refreshInterval}
                onChange={(e) => setRefreshInterval(Number(e.target.value))}
              >
                <option value={1}>1s</option>
                <option value={3}>3s</option>
                <option value={5}>5s</option>
                <option value={10}>10s</option>
              </select>
            </label>
          </div>
          <TerminalView paneId={paneId} interval={refreshInterval} />
        </>
      )}
    </div>
  );
}
