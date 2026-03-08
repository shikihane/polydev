import { useState, useEffect, useRef } from 'react';

export default function TerminalView({ paneId, interval, onLines, onDead }) {
  const [lines, setLines] = useState([]);
  const [dead, setDead] = useState(false);
  const containerRef = useRef(null);

  useEffect(() => {
    setLines([]);
    setDead(false);

    const url = `/api/stream/capture/${encodeURIComponent(paneId)}?interval=${interval}`;
    const es = new EventSource(url);

    es.addEventListener('capture', (e) => {
      const data = JSON.parse(e.data);
      setLines(data.lines);
      onLines?.(data.lines);
    });

    es.addEventListener('dead', () => {
      setDead(true);
      onDead?.();
      es.close();
    });

    es.addEventListener('error', () => {
      // EventSource auto-reconnects on error
    });

    return () => {
      es.close();
    };
  }, [paneId, interval]);

  // Auto-scroll to bottom
  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [lines]);

  return (
    <div className="terminal-view" ref={containerRef}>
      {dead && (
        <div style={{ color: '#f85149', marginBottom: 8, fontSize: 12 }}>
          Session ended
        </div>
      )}
      <pre>{lines.join('\n')}</pre>
    </div>
  );
}
