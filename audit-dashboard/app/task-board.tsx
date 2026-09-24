'use client';

import { useEffect, useMemo, useState } from 'react';
import { auditTasks, statusLabels, statusOrder, type AuditTask, type Priority, type TaskStatus } from './audit-data';

const API_URL = (process.env.NEXT_PUBLIC_AUDIT_API_URL ?? 'http://localhost:3001').replace(/\/$/, '');
const priorityRank: Record<Priority, number> = { Severe: 0, High: 1, Medium: 2 };

type SyncState = 'connecting' | 'synced' | 'saving' | 'error';
type ListView = 'issues' | 'skipped';
type TaskProgressResponse = {
  version: number;
  updatedAt: string;
  tasks: Record<string, TaskStatus>;
};

type IconName = 'board' | 'shield' | 'speed' | 'package' | 'layers' | 'search' | 'download' | 'menu' | 'close' | 'arrow' | 'check' | 'clock' | 'copy';

function Icon({ name, size = 18 }: { name: IconName; size?: number }) {
  const paths: Record<IconName, React.ReactNode> = {
    board: <><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></>,
    shield: <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10Z"/>,
    speed: <><path d="M12 3a9 9 0 1 0 9 9"/><path d="m12 12 6-6"/></>,
    package: <><path d="m21 8-9-5-9 5 9 5 9-5Z"/><path d="m3 8 9 5 9-5v8l-9 5-9-5V8Z"/><path d="M12 13v8"/></>,
    layers: <><path d="m12 2 9 5-9 5-9-5 9-5Z"/><path d="m3 12 9 5 9-5"/><path d="m3 17 9 5 9-5"/></>,
    search: <><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></>,
    download: <><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></>,
    menu: <><path d="M4 7h16M4 12h16M4 17h16"/></>,
    close: <path d="m6 6 12 12M18 6 6 18"/>,
    arrow: <path d="m9 18 6-6-6-6"/>,
    check: <path d="m5 12 4 4L19 6"/>,
    clock: <><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
    copy: <><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></>,
  };
  return <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{paths[name]}</svg>;
}

function nextStatus(status: TaskStatus): TaskStatus {
  if (status === 'done' || status === 'skipped') return 'backlog';
  if (status === 'blocked') return 'in-progress';
  return ({ backlog: 'picked', picked: 'in-progress', 'in-progress': 'done' } as Partial<Record<TaskStatus, TaskStatus>>)[status] ?? 'backlog';
}

function actionLabel(status: TaskStatus) {
  return status === 'backlog' ? 'Pick for development' : status === 'picked' ? 'Start work' : status === 'in-progress' ? 'Mark complete' : status === 'blocked' ? 'Resume work' : status === 'skipped' ? 'Return to backlog' : 'Reopen task';
}

function CheckboxFilter<T extends string>({
  label,
  options,
  selected,
  onChange,
}: {
  label: string;
  options: Array<{ value: T; label: string }>;
  selected: T[];
  onChange: (values: T[]) => void;
}) {
  const selectedLabel = selected.length === 0
    ? 'All'
    : selected.length === 1
      ? options.find((option) => option.value === selected[0])?.label ?? selected[0]
      : `${selected.length} selected`;

  function toggle(value: T) {
    onChange(selected.includes(value)
      ? selected.filter((item) => item !== value)
      : [...selected, value]);
  }

  return (
    <details className="checkbox-filter">
      <summary>
        <span>{label}</span>
        <strong>{selectedLabel}</strong>
        <Icon name="arrow" size={14}/>
      </summary>
      <div className="checkbox-options" role="group" aria-label={`${label} filters`}>
        <button type="button" className={selected.length === 0 ? 'selected' : ''} onClick={() => onChange([])}>
          <span className="filter-check">{selected.length === 0 && <Icon name="check" size={13}/>}</span>
          All
        </button>
        {options.map((option) => {
          const checked = selected.includes(option.value);
          return (
            <label key={option.value}>
              <input type="checkbox" checked={checked} onChange={() => toggle(option.value)}/>
              <span className="filter-check">{checked && <Icon name="check" size={13}/>}</span>
              {option.label}
            </label>
          );
        })}
      </div>
    </details>
  );
}

export default function TaskBoard() {
  const [statuses, setStatuses] = useState<Record<string, TaskStatus>>({});
  const [search, setSearch] = useState('');
  const [priorities, setPriorities] = useState<Priority[]>([]);
  const [statusFilters, setStatusFilters] = useState<TaskStatus[]>([]);
  const [areaFilters, setAreaFilters] = useState<string[]>([]);
  const [scopeFilters, setScopeFilters] = useState<Array<'Latest' | 'Existing'>>([]);
  const [listView, setListView] = useState<ListView>('issues');
  const [sort, setSort] = useState<'priority' | 'id' | 'status'>('priority');
  const [selected, setSelected] = useState<AuditTask | null>(null);
  const [mobileNav, setMobileNav] = useState(false);
  const [showFilters, setShowFilters] = useState(false);
  const [copyResult, setCopyResult] = useState<'idle' | 'copied' | 'error'>('idle');
  const [syncState, setSyncState] = useState<SyncState>('connecting');

  useEffect(() => {
    let active = true;

    async function syncProgress() {
      try {
        const response = await fetch(`${API_URL}/api/tasks`, { cache: 'no-store' });
        if (!response.ok) throw new Error('Unable to load shared progress.');
        const progress = await response.json() as TaskProgressResponse;
        if (!active) return;
        setStatuses(progress.tasks);
        setSelected((current) => current
          ? { ...current, status: progress.tasks[current.id] ?? auditTasks.find((item) => item.id === current.id)?.status ?? current.status }
          : current);
        setSyncState('synced');
      } catch {
        if (active) setSyncState('error');
      }
    }

    void syncProgress();
    const poll = window.setInterval(() => void syncProgress(), 2000);
    return () => {
      active = false;
      window.clearInterval(poll);
    };
  }, []);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setSelected(null);
        setMobileNav(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  const tasks = useMemo(() => auditTasks.map((item) => ({ ...item, status: statuses[item.id] ?? item.status })), [statuses]);
  const areas = useMemo(() => Array.from(new Set(auditTasks.map((item) => item.area))).sort(), []);
  const counts = useMemo(() => ({
    total: tasks.filter((item) => item.status !== 'skipped').length,
    skipped: tasks.filter((item) => item.status === 'skipped').length,
    severe: tasks.filter((item) => item.priority === 'Severe' && item.status !== 'done' && item.status !== 'skipped').length,
    active: tasks.filter((item) => item.status === 'picked' || item.status === 'in-progress').length,
    done: tasks.filter((item) => item.status === 'done').length,
  }), [tasks]);
  const pickedTasks = useMemo(
    () => tasks.filter((item) => item.status === 'picked' || item.status === 'in-progress'),
    [tasks],
  );

  const visibleTasks = useMemo(() => {
    const query = search.trim().toLowerCase();
    return tasks
      .filter((item) => listView === 'skipped' ? item.status === 'skipped' : item.status !== 'skipped')
      .filter((item) => !query || `${item.id} ${item.title} ${item.summary} ${item.action} ${item.area} ${item.files.join(' ')}`.toLowerCase().includes(query))
      .filter((item) => priorities.length === 0 || priorities.includes(item.priority))
      .filter((item) => statusFilters.length === 0 || statusFilters.includes(item.status))
      .filter((item) => areaFilters.length === 0 || areaFilters.includes(item.area))
      .filter((item) => scopeFilters.length === 0 || scopeFilters.some((scope) => scope === 'Latest' ? item.latest : !item.latest))
      .sort((a, b) => {
        if (sort === 'id') return a.id.localeCompare(b.id);
        if (sort === 'status') return statusOrder.indexOf(a.status) - statusOrder.indexOf(b.status) || priorityRank[a.priority] - priorityRank[b.priority];
        return priorityRank[a.priority] - priorityRank[b.priority] || a.id.localeCompare(b.id);
      });
  }, [tasks, listView, search, priorities, statusFilters, areaFilters, scopeFilters, sort]);

  const progress = counts.total ? Math.round((counts.done / counts.total) * 100) : 0;

  async function updateTask(id: string, next: TaskStatus) {
    setCopyResult('idle');
    const previous = statuses[id];
    const originalStatus = auditTasks.find((item) => item.id === id)?.status ?? 'backlog';
    setStatuses((current) => ({ ...current, [id]: next }));
    setSelected((current) => current?.id === id ? { ...current, status: next } : current);
    setSyncState('saving');

    try {
      const response = await fetch(`${API_URL}/api/tasks/${encodeURIComponent(id)}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status: next }),
      });
      if (!response.ok) throw new Error('Unable to save shared progress.');
      const progress = await response.json() as TaskProgressResponse;
      const persistedStatus = progress.tasks[id] ?? originalStatus;
      setStatuses((current) => ({ ...current, [id]: persistedStatus }));
      setSelected((current) => current?.id === id ? { ...current, status: persistedStatus } : current);
      setSyncState('synced');
    } catch {
      setStatuses((current) => {
        const restored = { ...current };
        if (previous === undefined) delete restored[id];
        else restored[id] = previous;
        return restored;
      });
      setSelected((current) => current?.id === id ? { ...current, status: previous ?? originalStatus } : current);
      setSyncState('error');
    }
  }

  async function resetProgress() {
    if (!window.confirm('Reset every task to its original audit status?')) return;
    setSyncState('saving');
    try {
      const response = await fetch(`${API_URL}/api/tasks`, { method: 'DELETE' });
      if (!response.ok) throw new Error('Unable to reset shared progress.');
      const progress = await response.json() as TaskProgressResponse;
      setStatuses(progress.tasks);
      setSelected((current) => current
        ? { ...current, status: progress.tasks[current.id] ?? auditTasks.find((item) => item.id === current.id)?.status ?? current.status }
        : current);
      setSyncState('synced');
    } catch {
      setSyncState('error');
    }
  }

  async function copyAgentPrompt() {
    if (pickedTasks.length === 0) return;
    const taskIds = pickedTasks.map((item) => item.id).join(', ');
    const prompt = `Please pick up and implement these CardVault audit tasks: ${taskIds}. Review each Task ID's exact issue, priority rationale, required changes, and relevant files in the audit dashboard before changing code. Process the Task IDs strictly one at a time in the listed order. For each task: (1) implement the fix safely while preserving existing behavior; (2) write or update focused test cases for the change; (3) analyze and verify that the issue is properly fixed by reviewing the resulting behavior and running the focused tests plus the relevant analysis and regression suites; and (4) only after the implementation and verification pass, report that task's result and move to the next Task ID. If a task cannot be verified or is blocked, stop before starting the next task and report the blocker. At the end, report which Task IDs were completed, blocked, or remain pending.`;
    try {
      await navigator.clipboard.writeText(prompt);
      setCopyResult('copied');
    } catch {
      try {
        const field = document.createElement('textarea');
        field.value = prompt;
        field.style.position = 'fixed';
        field.style.opacity = '0';
        document.body.appendChild(field);
        field.select();
        document.execCommand('copy');
        field.remove();
        setCopyResult('copied');
      } catch {
        setCopyResult('error');
      }
    }
  }

  function resetFilters() {
    setSearch(''); setPriorities([]); setStatusFilters([]); setAreaFilters([]); setScopeFilters([]); setSort('priority');
  }

  function showIssueView(area: string | null) {
    setListView('issues');
    setAreaFilters(area === null ? [] : [area]);
    setStatusFilters([]);
    setMobileNav(false);
  }

  function showSkippedView() {
    setListView('skipped');
    setAreaFilters([]);
    setStatusFilters([]);
    setMobileNav(false);
  }

  function exportProgress() {
    const payload = {
      project: 'CardVault',
      exportedAt: new Date().toISOString(),
      summary: counts,
      tasks: tasks.map(({ id, title, priority: taskPriority, area: taskArea, status: taskStatus }) => ({
        id,
        title,
        priority: taskPriority,
        area: taskArea,
        status: taskStatus,
      })),
    };
    const url = URL.createObjectURL(new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = `cardvault-audit-${new Date().toISOString().slice(0, 10)}.json`;
    link.click();
    URL.revokeObjectURL(url);
  }

  const navItems = [
    { label: 'All issues', icon: 'board' as const, area: null },
    { label: 'Security', icon: 'shield' as const, area: 'Security' },
    { label: 'Performance', icon: 'speed' as const, area: 'Performance' },
    { label: 'APK size', icon: 'package' as const, area: 'APK Size' },
    { label: 'Dependencies', icon: 'layers' as const, area: 'Dependencies' },
  ];

  const sidebar = (
    <>
      <div className="brand-lockup">
        <span className="brand-mark">CV</span>
        <span><strong>CardVault</strong><small>Audit workspace</small></span>
      </div>
      <nav className="side-nav" aria-label="Audit areas">
        <span className="nav-label">Workspace</span>
        {navItems.map((item) => (
          <button key={item.label} className={listView === 'issues' && (item.area === null ? areaFilters.length === 0 : areaFilters.length === 1 && areaFilters[0] === item.area) ? 'active' : ''} onClick={() => showIssueView(item.area)}>
            <Icon name={item.icon}/><span>{item.label}</span>
            <b>{item.area === null ? counts.total : tasks.filter((taskItem) => taskItem.status !== 'skipped' && taskItem.area === item.area).length}</b>
          </button>
        ))}
        <span className="nav-label nav-label-later">Later</span>
        <button className={listView === 'skipped' ? 'active' : ''} onClick={showSkippedView}>
          <Icon name="clock"/><span>Skipped</span><b>{counts.skipped}</b>
        </button>
      </nav>
      <div className="sidebar-note">
        <span className="live-dot"/> Audit refreshed
        <strong>25 Aug 2026</strong>
        <p>Based on current repository structure and the latest release changes.</p>
      </div>
    </>
  );

  return (
    <main className="app-shell">
      <aside className="sidebar">{sidebar}</aside>
      {mobileNav && <div className="mobile-scrim" onClick={() => setMobileNav(false)}><aside className="mobile-sidebar" onClick={(event) => event.stopPropagation()}><button className="icon-button close-nav" aria-label="Close navigation" onClick={() => setMobileNav(false)}><Icon name="close"/></button>{sidebar}</aside></div>}

      <section className="workspace">
        <header className="topbar">
          <button className="icon-button mobile-menu" aria-label="Open navigation" onClick={() => setMobileNav(true)}><Icon name="menu"/></button>
          <div className="breadcrumb"><span>CardVault</span><Icon name="arrow" size={14}/><strong>Audit command center</strong></div>
          <span className={`server-sync ${syncState}`} role="status" aria-live="polite">
            <span/>{syncState === 'synced' ? 'Shared progress' : syncState === 'saving' ? 'Saving…' : syncState === 'error' ? 'Server offline' : 'Connecting…'}
          </span>
          <button className="secondary-button" onClick={exportProgress}><Icon name="download"/><span>Export progress</span></button>
        </header>

        <div className="content-wrap">
          <section className="hero">
            <div>
              <span className="eyebrow">Remediation command center</span>
              <h1>Turn findings into shipped fixes.</h1>
              <p>Prioritize the current CardVault audit, assign work to your active queue, and keep remediation progress visible in one place.</p>
            </div>
            <div className="progress-orbit" style={{ background: `conic-gradient(var(--acid) ${progress * 3.6}deg, rgba(255,255,255,.11) 0deg)` }} aria-label={`${progress}% complete`}>
              <div><strong>{progress}%</strong><span>complete</span></div>
            </div>
          </section>

          <section className="metrics" aria-label="Audit summary">
            <article><span>All findings</span><strong>{counts.total}</strong><small>Across {areas.length} work areas</small></article>
            <article className="danger-metric"><span>Severe open</span><strong>{counts.severe}</strong><small>Resolve before release</small></article>
            <article><span>Active queue</span><strong>{counts.active}</strong><small>Picked or in development</small></article>
            <article><span>Completed</span><strong>{counts.done}</strong><small>{progress}% of the audit</small></article>
          </section>

          <section className="development-queue" aria-labelledby="development-queue-title">
            <div className="queue-heading">
              <div><span className="eyebrow dark">Active handoff</span><h2 id="development-queue-title">Picked for development</h2><p>Tasks marked Picked or In progress are shared across every connected browser.</p></div>
              <button className="copy-prompt-button" onClick={copyAgentPrompt} disabled={pickedTasks.length === 0}><Icon name={copyResult === 'copied' ? 'check' : 'copy'}/>{copyResult === 'copied' ? 'Prompt copied' : copyResult === 'error' ? 'Copy failed' : 'Copy AI agent prompt'}</button>
            </div>
            {pickedTasks.length > 0 ? (
              <div className="queue-tasks">{pickedTasks.map((item) => <article key={item.id}>
                <button className="queue-open" onClick={() => setSelected(item)}><strong>{item.id}</strong><span>{item.title}</span><i>{statusLabels[item.status]}</i></button>
                <div className="queue-tile-actions">
                  <button className="queue-done" aria-label={`Mark ${item.id} as done`} title="Mark done" onClick={() => updateTask(item.id, 'done')}><Icon name="check" size={14}/></button>
                  <button className="queue-remove" aria-label={`Move ${item.id} back to backlog`} title="Move back to backlog" onClick={() => updateTask(item.id, 'backlog')}><Icon name="close" size={14}/></button>
                </div>
              </article>)}</div>
            ) : (
              <div className="queue-empty"><span>Nothing picked yet.</span> Use a task’s status control or “Pick for development” button to add it here.</div>
            )}
            <p className="copy-feedback" aria-live="polite">{copyResult === 'copied' ? `Copied ${pickedTasks.map((item) => item.id).join(', ')} with implementation instructions.` : copyResult === 'error' ? 'The browser blocked clipboard access. Please try again.' : ''}</p>
          </section>

          <section className="board-panel">
            <div className="board-heading">
              <div><span className="eyebrow dark">{listView === 'skipped' ? 'Saved for later' : 'Current audit'}</span><h2>{listView === 'skipped' ? 'Skipped tasks' : 'Issue register'}</h2><p>{visibleTasks.length} of {listView === 'skipped' ? counts.skipped : counts.total} tasks visible</p></div>
              <button className="filter-toggle" onClick={() => setShowFilters((value) => !value)} aria-expanded={showFilters}>Filters <span>{[priorities, statusFilters, areaFilters, scopeFilters].filter((values) => values.length > 0).length}</span></button>
            </div>

            <div className={`filters ${showFilters ? 'show' : ''}`}>
              <label className="filter-field search-field"><span className="sr-only">Search tasks</span><Icon name="search"/><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search ID, issue or area…"/></label>
              <CheckboxFilter label="Priority" options={(['Severe', 'High', 'Medium'] as Priority[]).map((value) => ({ value, label: value }))} selected={priorities} onChange={setPriorities}/>
              <CheckboxFilter label="Status" options={statusOrder.filter((value) => value !== 'skipped').map((value) => ({ value, label: statusLabels[value] }))} selected={statusFilters} onChange={setStatusFilters}/>
              <CheckboxFilter label="Area" options={areas.map((value) => ({ value, label: value }))} selected={areaFilters} onChange={setAreaFilters}/>
              <CheckboxFilter label="Finding" options={[{ value: 'Latest' as const, label: 'Latest audit' }, { value: 'Existing' as const, label: 'Existing' }]} selected={scopeFilters} onChange={setScopeFilters}/>
              <label className="filter-field"><span>Sort</span><select value={sort} onChange={(event) => setSort(event.target.value as typeof sort)}><option value="priority">Priority</option><option value="id">Task ID</option><option value="status">Status</option></select></label>
            </div>

            <div className="active-filter-row">
              <div>
                {areaFilters.map((value) => <button key={`area-${value}`} onClick={() => setAreaFilters((current) => current.filter((item) => item !== value))}>{value}<Icon name="close" size={13}/></button>)}
                {priorities.map((value) => <button key={`priority-${value}`} onClick={() => setPriorities((current) => current.filter((item) => item !== value))}>{value}<Icon name="close" size={13}/></button>)}
                {statusFilters.map((value) => <button key={`status-${value}`} onClick={() => setStatusFilters((current) => current.filter((item) => item !== value))}>{statusLabels[value]}<Icon name="close" size={13}/></button>)}
                {scopeFilters.map((value) => <button key={`scope-${value}`} onClick={() => setScopeFilters((current) => current.filter((item) => item !== value))}>{value === 'Latest' ? 'Latest audit' : value}<Icon name="close" size={13}/></button>)}
              </div>
              {(search || priorities.length > 0 || statusFilters.length > 0 || areaFilters.length > 0 || scopeFilters.length > 0) && <button className="reset-link" onClick={resetFilters}>Reset filters</button>}
            </div>

            <div className="task-list">
              {visibleTasks.map((item) => (
                <article key={item.id} className={`task-card priority-${item.priority.toLowerCase()} status-${item.status}`}>
                  <button className="task-main" onClick={() => setSelected(item)} aria-label={`Open ${item.id}: ${item.title}`}>
                    <span className="priority-stripe"/>
                    <span className="task-id-row"><b>{item.id}</b>{item.latest && <em>New finding</em>}</span>
                    <strong>{item.title}</strong>
                    <p>{item.summary}</p>
                    <span className="tag-row"><i className={`priority-tag ${item.priority.toLowerCase()}`}>{item.priority}</i><i>{item.area}</i></span>
                  </button>
                  <div className="task-actions">
                    <label><span className="sr-only">Status for {item.id}</span><select className={`status-select status-${item.status}`} value={item.status} onChange={(event) => updateTask(item.id, event.target.value as TaskStatus)}>{statusOrder.map((statusItem) => <option key={statusItem} value={statusItem}>{statusLabels[statusItem]}</option>)}</select></label>
                    <button className="primary-action" onClick={() => updateTask(item.id, nextStatus(item.status))}>{item.status === 'done' || item.status === 'skipped' ? <Icon name="clock"/> : <Icon name="check"/>}{actionLabel(item.status)}</button>
                    {item.status !== 'skipped' && <button className="skip-action" onClick={() => updateTask(item.id, 'skipped')}><Icon name="clock"/>Skip for now</button>}
                  </div>
                </article>
              ))}
              {visibleTasks.length === 0 && <div className="empty-state"><span>0</span><h3>{listView === 'skipped' && counts.skipped === 0 ? 'Nothing skipped' : 'No findings match'}</h3><p>{listView === 'skipped' && counts.skipped === 0 ? 'Tasks you skip will stay here until you are ready to pick them up again.' : 'Try clearing a filter or searching with a different term.'}</p>{(search || priorities.length > 0 || statusFilters.length > 0 || areaFilters.length > 0 || scopeFilters.length > 0) && <button className="secondary-button" onClick={resetFilters}>Reset filters</button>}</div>}
            </div>
          </section>

          <footer><span>CardVault audit workspace</span><button onClick={() => void resetProgress()}>Reset all progress</button></footer>
        </div>
      </section>

      {selected && <div className="drawer-scrim" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelected(null); }}>
        <aside className="task-drawer" role="dialog" aria-modal="true" aria-labelledby="drawer-title">
          <div className="drawer-top"><span className={`priority-tag ${selected.priority.toLowerCase()}`}>{selected.priority}</span><button className="icon-button" aria-label="Close task details" onClick={() => setSelected(null)}><Icon name="close"/></button></div>
          <span className="drawer-id">{selected.id}{selected.latest && <em>Latest audit</em>}</span>
          <h2 id="drawer-title">{selected.title}</h2>
          <section className="drawer-section"><span>Exact issue</span><p className="drawer-summary">{selected.summary}</p></section>
          <section className={`severity-rationale ${selected.priority.toLowerCase()}`}><span>Why this is {selected.priority}</span><p>{selected.risk}</p></section>
          <div className="drawer-meta"><div><span>Area</span><strong>{selected.area}</strong></div><div><span>Current state</span><strong>{statusLabels[selected.status]}</strong></div></div>
          <section className="recommendation"><span>Required changes</span><p>{selected.action}</p></section>
          <section className="drawer-files"><span>Relevant files</span><div className="file-list">{selected.files.map((file) => <code key={file}>{file}</code>)}</div><small>Starting points verified against the current repository. The final change may touch related tests or generated platform files.</small></section>
          <label className="drawer-status"><span>Update status</span><select value={selected.status} onChange={(event) => updateTask(selected.id, event.target.value as TaskStatus)}>{statusOrder.map((item) => <option key={item} value={item}>{statusLabels[item]}</option>)}</select></label>
          <button className="drawer-action" onClick={() => updateTask(selected.id, nextStatus(selected.status))}>{actionLabel(selected.status)}<Icon name="arrow"/></button>
          {selected.status !== 'skipped' && <button className="drawer-skip-action" onClick={() => updateTask(selected.id, 'skipped')}><Icon name="clock"/>Skip this task for now</button>}
          <p className="persistence-note">Progress is shared by the local dashboard server and written to the repository JSON file.</p>
        </aside>
      </div>}
    </main>
  );
}
