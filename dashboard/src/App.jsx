import { useState, useEffect, useCallback } from 'react';
import Dashboard from './components/Dashboard';

export default function App() {
  const [sessions, setSessions] = useState([]);
  const [tasks, setTasks] = useState([]);
  const [error, setError] = useState(null);
  const [lastRefresh, setLastRefresh] = useState(null);

  const refresh = useCallback(async () => {
    try {
      const [sessRes, taskRes] = await Promise.all([
        fetch('/api/sessions'),
        fetch('/api/tasks'),
      ]);
      if (!sessRes.ok || !taskRes.ok) throw new Error('API error');
      const sessData = await sessRes.json();
      const taskData = await taskRes.json();
      setSessions(sessData.sessions);
      setTasks(taskData.tasks);
      setError(null);
      setLastRefresh(new Date());
    } catch (err) {
      setError(err.message);
    }
  }, []);

  useEffect(() => {
    refresh();
    const timer = setInterval(refresh, 5000);
    return () => clearInterval(timer);
  }, [refresh]);

  return (
    <Dashboard
      sessions={sessions}
      tasks={tasks}
      error={error}
      lastRefresh={lastRefresh}
    />
  );
}
