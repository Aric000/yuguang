import React, { Component, useEffect, useRef, useState, createContext, useContext, useCallback, type ReactNode, type PointerEvent as ReactPointerEvent } from 'react';
import { createRoot } from 'react-dom/client';
import type { Bridge, State, Preferences } from './types';
import { clock, isLive, isUpcoming, score, startLabel, status } from './format';
import { previewBridge } from './preview';
import catalog from '../public/teams/catalog.json';
import './style.css';

const bridge = window.yuguang || (new URLSearchParams(location.search).has('demo') ? previewBridge() : undefined);
const teamCatalog = catalog as Record<string, { dayColor?: string; nightColor?: string }>;
const BridgeContext = createContext<Bridge | undefined>(bridge);
function useCommand() { const active = useContext(BridgeContext); return useCallback(async (command: string, value?: unknown) => { if (!active) throw new Error('请从余光桌面应用打开'); return active.command(command, value); }, [active]); }
function Icon({ name }: { name: 'settings' | 'close' | 'compact' | 'expand' | 'switch' | 'back' | 'refresh' | 'star' | 'chevron' }) {
  const paths = { settings: 'M3 5h10m4 0h4M3 12h4m4 0h10M3 19h12m4 0h2M13 2v6M7 9v6m8 1v6', close: 'm6 6 12 12M6 18 18 6', compact: 'M4 4h16M4 20h16m8-18v7m-3-3 3 3 3-3m-3 16v-7m-3 3 3-3 3 3', expand: 'M8 3H3v5m0-5 7 7m6 11h5v-5m0 5-7-7', switch: 'M4 7h16m-4-4 4 4-4 4M20 17H4m4-4-4 4 4 4', back: 'M20 12H4m7-7-7 7 7 7', refresh: 'M20 7v5h-5M4 17a8 8 0 0 0 14 1M20 7A8 8 0 0 0 6 6L3 9m0-5v5h5', star: 'm12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2L12 17.3l-5.6 2.9 1.1-6.2L3 9.6l6.2-.9Z', chevron: 'm9 5 7 7-7 7' };
  return <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d={paths[name]}/></svg>;
}
function Button({ name, label, onClick }: { name: Parameters<typeof Icon>[0]['name']; label: string; onClick: () => void }) { return <button className="icon-button" type="button" aria-label={label} title={label} onClick={onClick}><Icon name={name}/></button>; }
function Logo({ size = 28 }: { size?: number }) { return <img className="brand" src="./logo.svg" alt="余光之眼" width={size} height={size}/>; }
function TeamLogo({ name, size = 48 }: { name: string; size?: number }) { const [failed, setFailed] = useState(false); return failed || !teamCatalog[name] ? <span className="team-fallback" style={{ width: size, height: size }}>{name.slice(0, 1)}</span> : <img className="team-logo" src={`./teams/${encodeURIComponent(name)}.png`} alt={`${name}队徽`} width={size} height={size} onError={() => setFailed(true)}/>; }
function ErrorLine({ text, retry }: { text: string; retry: () => void }) { return <div className="error-line" role="status"><span>{text}</span><button onClick={retry}>重试</button></div>; }
function useDrag(resize = false, doubleClick?: () => void) {
  const call = useCommand();
  const active = useRef(false);
  return {
    onPointerDown: (e: ReactPointerEvent<HTMLDivElement>) => {
      if (e.button !== 0 || (e.target as HTMLElement).closest('button,input,select,a')) return;
      if (e.detail === 2 && doubleClick) { doubleClick(); return; }
      active.current = true; e.currentTarget.setPointerCapture(e.pointerId); e.preventDefault();
      void call(resize ? 'resize-start' : 'drag-start', { x: e.screenX, y: e.screenY });
    },
    onPointerMove: (e: ReactPointerEvent<HTMLDivElement>) => { if (active.current) void call(resize ? 'resize-move' : 'drag-move', { x: e.screenX, y: e.screenY }); },
    onPointerUp: (e: ReactPointerEvent<HTMLDivElement>) => { if (active.current) { active.current = false; e.currentTarget.releasePointerCapture(e.pointerId); void call('drag-end'); } },
    onPointerCancel: () => { if (active.current) { active.current = false; void call('drag-end'); } }
  };
}
function TitleBar({ state }: { state: State }) {
  const call = useCommand();
  const drag = useDrag();
  return <header className="titlebar"><div className="title-drag" {...drag}><Logo/><strong>余光</strong>{state.demo && <span className="demo-label">演示</span>}</div><div className="title-actions">{state.selectedMatch && <Button name="compact" label={`精简模式（${state.preferences.rows} 行）`} onClick={() => void call('mode')}/>}<Button name={state.page === 'settings' ? 'back' : 'settings'} label={state.page === 'settings' ? '返回' : '设置'} onClick={() => void call('page', state.page === 'settings' ? (state.selectedMatch ? 'live' : 'matches') : 'settings')}/><Button name="close" label="隐藏窗口" onClick={() => void call('hide')}/></div></header>;
}
function MatchList({ state }: { state: State }) {
  const call = useCommand();
  const favorites = state.preferences.favorites;
  const matches = [...(state.days.find(d => d.day === state.selectedDay)?.matchList || [])].filter(m => state.teamFilter === '全部球队' || [m.homeTeamName, m.awayTeamName].includes(state.teamFilter)).sort((a,b) => Number([b.homeTeamName,b.awayTeamName].some(t => favorites.includes(t))) - Number([a.homeTeamName,a.awayTeamName].some(t => favorites.includes(t))) || Number(isLive(b))-Number(isLive(a)) || (a.matchTime || '').localeCompare(b.matchTime || ''));
  const teams = [...new Set(state.days.flatMap(d => d.matchList.flatMap(m => [m.awayTeamName,m.homeTeamName])))].sort();
  return <section className="schedule page"><div className="section-heading"><h1>比赛日</h1><div>{state.selectedMatch && <button onClick={() => void call('page', 'live')}>继续观看</button>}<Button name="refresh" label="刷新赛程" onClick={() => void call('refresh')}/></div></div><div className="filters"><select aria-label="比赛日期" value={state.selectedDay} onChange={e => void call('date', e.target.value)}>{state.days.map(d => <option key={d.day} value={d.day}>{d.dayBlock}</option>)}</select><select aria-label="筛选球队" value={state.teamFilter} onChange={e => void call('filter',e.target.value)}><option>全部球队</option>{teams.map(t => <option key={t}>{t}</option>)}</select></div>{state.teamFilter !== '全部球队' && <button className="favorite-filter" onClick={() => void call('favorite',state.teamFilter)}>{favorites.includes(state.teamFilter) ? '已关注' : '关注'}{state.teamFilter}</button>}{state.scheduleError && <ErrorLine text={state.scheduleError} retry={() => void call('refresh')}/>}<div className="match-scroll">{matches.map(m => <button className="match-card" key={m.matchId} onClick={() => void call('select',m.matchId)} aria-label={`${m.awayTeamName} vs ${m.homeTeamName}，${status(m)}，打开文字直播`}><div className="match-meta"><span className={isLive(m) ? 'live-status' : ''}>{isLive(m) && <i/>}{isUpcoming(m) ? startLabel(m) : status(m)}</span><Icon name="chevron"/></div>{(['away','home'] as const).map(side => { const name = side === 'away' ? m.awayTeamName : m.homeTeamName; return <div className="match-team" key={side}>{!state.preferences.simple && <TeamLogo name={name} size={26}/>}<span>{name}</span>{favorites.includes(name) && <span className="favorite-dot"><Icon name="star"/></span>}<b>{isUpcoming(m) ? '—' : (side === 'away' ? m.awayScore : m.homeScore) ?? '—'}</b></div>; })}</button>)}{!matches.length && <div className="empty"><strong>{state.loadingSchedule ? '正在获取赛程' : '这一天没有相关比赛'}</strong><span>{state.loadingSchedule ? '连接虎扑赛事服务' : '换个日期，或查看全部球队。'}</span></div>}</div></section>;
}
function LiveView({ state, now }: { state: State; now: number }) {
  const call = useCommand();
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => { if (state.following && list.current) list.current.scrollTop = 0; }, [state.entries[0]?.id, state.following]);
  const m = state.selectedMatch;
  if (!m) return <div className="empty"><h1>选择一场比赛</h1><button onClick={() => void call('page','matches')}>查看赛程</button></div>;
  const error = state.matchError || state.textError;
  const entries = state.following ? state.entries : state.frozenEntries;
  const age = state.scoreUpdatedAt ? Math.max(0, Math.floor((now-state.scoreUpdatedAt)/1000)) : null;
  return <section className="live-view"><div className="scoreboard"><div className="league-line"><strong>NBA</strong><span>{m.competitionStageDesc || '篮球赛事'}</span><button onClick={() => void call('page','matches')}>赛程 <Icon name="chevron"/></button></div><div className="versus">{(['away','home'] as const).map((side,index) => { const name = side === 'away' ? m.awayTeamName : m.homeTeamName; return <React.Fragment key={side}>{index === 1 && <div className="versus-label"><span>{isUpcoming(m) ? '对阵' : m.matchStatus === 'COMPLETED' ? '终场' : '直播'}</span><strong>VS</strong></div>}<div className="score-team">{!state.preferences.simple && <div className="crest-field" style={{ backgroundColor: `#${teamCatalog[name]?.dayColor || '777777'}10` }}><TeamLogo name={name} size={58}/></div>}<span className="team-name">{name}</span><strong className="score-number">{isUpcoming(m) ? '—' : (side === 'away' ? m.awayScore : m.homeScore) ?? '—'}</strong><button className={`favorite-button ${state.preferences.favorites.includes(name) ? 'is-favorite' : ''}`} aria-label={`${state.preferences.favorites.includes(name) ? '取消关注' : '关注'}${name}`} onClick={() => void call('favorite',name)}>{side === 'away' ? '客场' : '主场'}<Icon name="star"/></button></div></React.Fragment>; })}</div><div className="game-status">{isLive(m) && <i/>}{isUpcoming(m) ? startLabel(m) : status(m)}</div><div className="team-colors"><span style={{ background: `#${teamCatalog[m.awayTeamName]?.dayColor || '647481'}` }}/><span style={{ background: `#${teamCatalog[m.homeTeamName]?.dayColor || '647481'}` }}/></div></div><div className="feed-header"><h1>文字直播</h1><button onClick={() => void call('following')}>{state.following ? '阅读历史' : `回到最新${state.unread ? ` · ${state.unread}` : ''}`}</button></div>{error && <ErrorLine text={error} retry={() => void call('retry')}/>}<div className="feed" ref={list} onWheel={() => { if (state.following && state.entries.length) void call('following'); }}>{entries.length ? entries.map((entry,index) => <article className="entry" key={entry.id}><div><time>{clock(entry.time)}</time>{index===0 && state.following && <span>最新</span>}</div><p>{entry.content}</p></article>) : <div className="empty"><strong>{state.loadingLive ? '正在连接直播' : isUpcoming(m) ? '等待开赛' : '暂时没有文字内容'}</strong><span>{isUpcoming(m) ? '比赛开始后自动更新' : '有新消息时会自动出现在这里'}</span></div>}</div><div className="freshness"><span><i className={!error && age != null && age < 30 ? 'fresh' : ''}/>{age == null ? '等待比分更新' : `比分更新于 ${age} 秒前`}</span><span>{state.demo ? '示例数据' : m.matchStatus === 'COMPLETED' ? '已结束' : '自动更新'}</span></div></section>;
}
function Settings({ state }: { state: State }) {
  const call = useCommand();
  const [recording, setRecording] = useState(false);
  const update = (patch: Partial<Preferences>) => void call('preferences',patch);
  useEffect(() => {
    if (!recording) return;
    const keydown = (e: KeyboardEvent) => {
      e.preventDefault(); e.stopPropagation();
      if (e.key === 'Escape') { setRecording(false); return; }
      if (['Control','Meta','Alt','Shift'].includes(e.key) || !(e.ctrlKey || e.altKey || e.metaKey)) return;
      const key = e.code === 'Backquote' ? '`' : e.key === ' ' ? 'Space' : e.key.length === 1 ? e.key.toUpperCase() : e.key;
      const accelerator = [e.ctrlKey && 'Control',e.metaKey && 'Command',e.altKey && 'Alt',e.shiftKey && 'Shift',key].filter(Boolean).join('+');
      void call('preferences',{ shortcut: accelerator }); setRecording(false);
    };
    window.addEventListener('keydown',keydown,true); return () => window.removeEventListener('keydown',keydown,true);
  },[recording]);
  const toggle = (key: 'simple' | 'pinned' | 'scoreOnly' | 'menuScore', title: string, detail: string) => <label className="setting-row"><span><strong>{title}</strong><small>{detail}</small></span><input type="checkbox" role="switch" aria-label={title} checked={state.preferences[key]} onChange={e => update({ [key]: e.target.checked })}/></label>;
  return <section className="settings page"><h1>偏好设置</h1><div className="brand-setting"><Logo size={52}/><div><strong>余光之眼</strong><p>眼睛与篮筐，也是一眼就能看见的比赛。</p></div></div><div className="shortcut-setting"><h2>全局隐藏快捷键</h2><p>随时隐藏，再按一次恢复。录制时按 Esc 取消。</p><div><button className="shortcut-key" onClick={() => setRecording(true)}>{recording ? '请按下组合键…' : state.preferences.shortcut}</button><button onClick={() => update({ shortcut: 'Control+`' })}>恢复默认</button></div>{state.shortcutError && <p role="alert">{state.shortcutError}</p>}</div><div className="theme-setting"><h2>外观</h2><div role="group" aria-label="外观" className="theme-options">{(['system','light','dark'] as const).map((theme,i) => <button aria-pressed={state.preferences.theme===theme} key={theme} onClick={() => update({ theme })}>{['跟随系统','雾白','炭黑'][i]}</button>)}</div></div>{toggle('simple','启用简洁模式','纯文字、不显示队徽；下次启动仍使用。')}{toggle('pinned','窗口置顶','浮在普通窗口之上')}<label className="setting-row"><span><strong>精简模式显示行数</strong><small>1–6 行，包含比分行；多行显示最新解说。</small></span><select aria-label="精简模式显示行数" value={state.preferences.rows} onChange={e => update({ rows: Number(e.target.value) })}>{[1,2,3,4,5,6].map(n => <option key={n} value={n}>{n} 行</option>)}</select></label>{toggle('scoreOnly','单行只看比分','显示 1 行时省略文字解说')}{toggle('menuScore','菜单栏显示比分', state.platform === 'win32' ? 'Windows 托盘悬停和菜单显示比分' : '窗口隐藏后也能看一眼')}<div className="about"><strong>安静地看一场球。</strong><p>余光 {state.version} · NBA 文字直播<br/>无声音、无推送、不抢输入焦点。<br/>数据由虎扑提供，可能存在延迟。</p></div></section>;
}
function Compact({ state }: { state: State }) {
  const call = useCommand();
  const drag = useDrag(false, () => void call('mode'));
  const m = state.selectedMatch;
  const latest = state.entries[0]?.content || (m && isUpcoming(m) ? `等待开赛 · ${startLabel(m)}` : '等待文字直播');
  return <div className="compact-content" {...drag} onContextMenu={e => { e.preventDefault(); void call('quick-menu'); }}><div className="compact-line"><div className="compact-score">{m ? <><span>{m.awayTeamName}</span><b>{score(m)}</b><span>{m.homeTeamName}</span></> : <span>余光 · 选择比赛</span>}</div>{state.preferences.rows === 1 && !state.preferences.scoreOnly && <span className="compact-text inline-text">{latest}</span>}<div className="compact-actions"><Button name="expand" label="展开直播" onClick={() => void call('mode')}/><Button name="switch" label="切换比赛" onClick={() => void call('quick-menu')}/></div></div>{Array.from({ length: state.preferences.rows-1 },(_,i) => <div className="compact-line extra-line" key={i}>{state.entries[i] ? <><time>{clock(state.entries[i].time)}</time><span className="compact-text">{state.entries[i].content}</span></> : i === 0 ? <span className="compact-text">{latest}</span> : null}</div>)}</div>;
}
export function App({ bridge: activeBridge }: { bridge: Bridge }) { return <BridgeContext.Provider value={activeBridge}><AppContent bridge={activeBridge}/></BridgeContext.Provider>; }
function AppContent({ bridge: activeBridge }: { bridge: Bridge }) {
  const [state,setState] = useState<State | null>(null); const [error,setError] = useState(''); const [now,setNow] = useState(Date.now());
  const resize = useDrag(true);
  useEffect(() => { const off = activeBridge.subscribe(setState); void activeBridge.getState().then(setState).catch(e => setError(e.message)); const timer = setInterval(() => setNow(Date.now()),1000); const rejection = (e: PromiseRejectionEvent) => { setError(String(e.reason?.message || e.reason)); e.preventDefault(); }; window.addEventListener('unhandledrejection',rejection); return () => { off(); clearInterval(timer); window.removeEventListener('unhandledrejection',rejection); }; },[activeBridge]);
  if (!state) return <div className="boot">{error || '正在打开余光…'}</div>;
  const dark = state.preferences.theme === 'dark' || (state.preferences.theme === 'system' && state.systemDark);
  const visible = !state.compact || state.hovered || state.menuOpen;
  return <main data-theme={dark ? 'dark' : 'light'} className={`app ${state.compact ? 'compact' : 'expanded'} ${visible ? 'chrome' : 'text-only'}`} style={state.compact ? { height: state.preferences.rows * 32 } : undefined}>{state.compact ? <Compact state={state}/> : <><TitleBar state={state}/><div className="sheet">{state.page==='matches' ? <MatchList state={state}/> : state.page==='settings' ? <Settings state={state}/> : <LiveView state={state} now={now}/>}</div><footer><span>{state.page==='settings' ? '更改自动保存' : '文字直播 · 来源虎扑'}</span><span>{state.preferences.shortcut} 隐藏 / 恢复</span></footer></>}{error && <div className="bridge-error" role="alert" onClick={() => setError('')}>{error}</div>}<div className="resize-handle" title="拖动调整窗口大小" {...resize}/></main>;
}
class ErrorBoundary extends Component<{ children: ReactNode },{ error: string }> { state = { error: '' }; static getDerivedStateFromError(e: Error) { return { error: e.message }; } render() { return this.state.error ? <div className="boot"><h1>界面暂时无法显示</h1><p>{this.state.error}</p><button onClick={() => location.reload()}>重新打开</button></div> : this.props.children; } }
if (document.getElementById('root')) createRoot(document.getElementById('root')!).render(<React.StrictMode><ErrorBoundary>{bridge ? <App bridge={bridge}/> : <div className="boot"><h1>余光</h1><p>请从桌面应用启动。</p></div>}</ErrorBoundary></React.StrictMode>);
