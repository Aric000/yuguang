import type { Bridge, State, Match } from './types';
export function previewBridge(): Bridge {
  const match: Match = { matchId: 'demo', awayTeamName: '湖人', homeTeamName: '勇士', awayScore: 102, homeScore: 99, matchStatus: 'INPROGRESS', frontEndMatchStatus: { desc: '第四节 剩2:18' } };
  const state: State = { days: [{ day: 'demo', dayBlock: '演示比赛日', matchList: [match, { ...match, matchId: 'demo-2', awayTeamName: '76人', homeTeamName: '尼克斯', awayScore: 106, homeScore: 100, matchStatus: 'COMPLETED', frontEndMatchStatus: { desc: '已结束' } }] }], selectedDay: 'demo', teamFilter: '全部球队', selectedMatch: match, entries: ['詹姆斯突破上篮得分，湖人领先三分。','库里借掩护三分出手，球弹筐而出。','湖人拿下防守篮板，准备发动反击。','暂停结束，比赛继续。'].map((content, i) => ({ id: String(i), content, time: `2026-10-21 10:18:${32 - 5*i}`, nickName: '演示解说' })), frozenEntries: [], following: true, unread: 0, loadingSchedule: false, loadingLive: false, scheduleError: '', matchError: '', textError: '', scoreUpdatedAt: Date.now(), textUpdatedAt: Date.now(), page: 'live', compact: false, hovered: true, menuOpen: false, shortcutError: '', preferences: { theme: 'light', pinned: true, rows: 1, simple: false, scoreOnly: false, menuScore: true, shortcut: 'Control+`', favorites: [], lastMatch: '' }, demo: true, systemDark: false, platform: 'preview', version: '0.2.0' };
  const listeners = new Set<(s: State) => void>();
  const emit = () => listeners.forEach(fn => fn(structuredClone(state)));
  return { getState: async () => structuredClone(state), subscribe: fn => { listeners.add(fn); return () => { listeners.delete(fn); }; }, command: async (name, value) => {
    if (name === 'mode') state.compact = !state.compact;
    if (name === 'page' && ['live','matches','settings'].includes(String(value))) { state.compact = false; state.page = value as State['page']; }
    if (name === 'select') { state.selectedMatch = state.days[0].matchList.find(m => m.matchId === value) || match; state.page = 'live'; }
    if (name === 'filter') state.teamFilter = String(value);
    if (name === 'preferences') { const previous = state.preferences.simple; Object.assign(state.preferences, value); if (previous !== state.preferences.simple) state.compact = state.preferences.simple; }
    if (name === 'favorite') state.preferences.favorites = state.preferences.favorites.includes(String(value)) ? state.preferences.favorites.filter(t => t !== value) : [...state.preferences.favorites, String(value)];
    if (name === 'following') { state.following = !state.following; state.frozenEntries = state.following ? [] : [...state.entries]; }
    emit();
  } };
}
