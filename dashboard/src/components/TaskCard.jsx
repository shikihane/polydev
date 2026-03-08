import { useState } from 'react';
import TerminalView from './TerminalView';
import { timeAgo } from '../utils.js';

export default function TaskCard({ item }) {
  const [expanded, setExpanded] = useState(false);
  const [refreshInterval, setRefreshInterval] = useState(3);
  const [lastLines, setLastLines] = useState(null);
  const [sessionDead, setSessionDead] = useState(false);
  const [killing, setKilling] = useState(false);
  const [closing, setClosing] = useState(false);

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

  const isAlive = !orphaned && paneId;
  const hasOutput = lastLines && lastLines.length > 0;

  const handleKill = async (e) => {
    e.stopPropagation();
    if (!window.confirm(`Kill session for "${branch}"?`)) return;
    setKilling(true);
    try {
      await fetch(`/api/kill/${encodeURIComponent(paneId)}`, { method: 'POST' });
    } catch {
      // next poll will reflect actual state
    }
    setKilling(false);
  };

  const handleClose = async (e) => {
    e.stopPropagation();
    if (!window.confirm(`Close pane "${branch}" from terminal?`)) return;
    setClosing(true);
    try {
      await fetch(`/api/close/${encodeURIComponent(paneId)}`, { method: 'POST' });
    } catch {
      // next poll will reflect actual state
    }
    setClosing(false);
  };

  const canToggle = isAlive || (orphaned && hasOutput);

  return (
    <div className={`task-card${orphaned ? ' orphaned' : ''}`}>
      <div className="card-header" onClick={() => canToggle && setExpanded(!expanded)}>
        <div className="card-header-left">
          <span className={`card-type ${orphaned ? 'ended' : type}`}>{type}</span>
          <span className="card-name">{branch || name}</span>
          {orphaned && <span className="card-type ended">ended</span>}
        </div>
        <div className="card-header-right">
          {isAlive && (
            <button
              className="kill-btn"
              disabled={killing}
              onClick={handleKill}
            >
              {killing ? 'Killing...' : 'Kill'}
            </button>
          )}
          {paneId && (
            <button
              className="close-btn"
              disabled={closing}
              onClick={handleClose}
            >
              {closing ? 'Closing...' : 'Close'}
            </button>
          )}
          {canToggle && (
            <button className="toggle-btn">
              {expanded ? '\u25B2 Hide Terminal' : '\u25BC Show Terminal'}
            </button>
          )}
        </div>
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

      {expanded && isAlive && (
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
          <TerminalView
            paneId={paneId}
            interval={refreshInterval}
            onLines={(lines) => setLastLines(lines)}
            onDead={() => setSessionDead(true)}
          />
        </>
      )}

      {expanded && orphaned && hasOutput && (
        <>
          <div className="terminal-toolbar">
            <span>Pane #{paneId} (ended)</span>
          </div>
          <div className="terminal-view">
            <div style={{ color: '#f85149', marginBottom: 8, fontSize: 12 }}>
              Session ended
            </div>
            <pre>{lastLines.join('\n')}</pre>
          </div>
        </>
      )}
    </div>
  );
}
