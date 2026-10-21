const JSONbig = require('json-bigint')({ storeAsString: true, protoAction: 'error', constructorAction: 'error' });
const { EventEmitter } = require('node:events');
const DEFAULTS = Object.freeze({ theme: 'system', pinned: true, rows: 1, simple: false, scoreOnly: false, menuScore: true, shortcut: 'Control+`', favorites: [], lastMatch: '' });
const isLive = m => m?.matchStatus === 'INPROGRESS';
const isUpcoming = m => m?.matchStatus === 'NOTSTARTED';
const isFinished = m => m?.matchStatus === 'COMPLETED';
const score = m => isUpcoming(m) ? 'vs' : `${m?.awayScore ?? '—'} : ${m?.homeScore ?? '—'}`;
const status = m => m?.frontEndMatchStatus?.desc || (isLive(m) ? '进行中' : isFinished(m) ? '已结束' : isUpcoming(m) ? '未开始' : '赛程待定');
const heading = m => m ? `${m.awayTeamName} ${score(m)} ${m.homeTeamName} · ${status(m)}` : '余光 · 安静地看一场球';
function plainText(raw) {
  return String(raw).replace(/<br\s*\/?>/gi, ' ').replace(/<[^>]*>/g, '').replace(/&(nbsp|lt|gt|quot|amp);/g, (_, key) => ({ nbsp: ' ', lt: '<', gt: '>', quot: '"', amp: '&' })[key]).trim();
}
function normalizeMatch(m) {
  if (!m || !['string', 'number'].includes(typeof m.matchId) || typeof m.homeTeamName !== 'string' || typeof m.awayTeamName !== 'string' || typeof m.matchStatus !== 'string') throw new Error('赛事服务返回的比赛数据无效');
  return { ...m, matchId: String(m.matchId), homeScore: Number.isSafeInteger(m.homeScore) ? m.homeScore : null, awayScore: Number.isSafeInteger(m.awayScore) ? m.awayScore : null };
}
function normalizeEntries(batch) {
  if (!Array.isArray(batch)) throw new Error('直播服务返回的文字列表无效');
  return batch.filter(e => e && typeof e.content === 'string').map(e => ({ id: String(e.commentId ?? `${e.time ?? ''}|${e.content}`), content: plainText(e.content), time: String(e.time ?? ''), nickName: String(e.nickName ?? '') }));
}
function mergeEntries(incoming, existing, limit = 500) {
  const seen = new Set();
  return [...incoming, ...existing].filter(e => !seen.has(e.id) && seen.add(e.id)).slice(0, limit);
}
function decode(raw) {
  const e = JSONbig.parse(raw);
  if (!e || e.success === false || (e.status != null && e.status !== 200)) throw new Error(e?.errorMsg || e?.msg || '直播服务返回异常');
  if (e.result == null) throw new Error('直播服务未返回有效数据');
  return e.result;
}
const ENDPOINTS = {
  schedule: ['https://games.mobileapi.hupu.com/1/7.5.60/basketballapi/scheduleList', { competitionTag: 'nba' }],
  match: ['https://games.mobileapi.hupu.com/1/7.5.60/basketballapi/singleMatch', {}],
  key: ['https://live-api.liangle.com/1/7.5.60/live/queryLiveActivityKey', { competitionType: 'basketball' }],
  text: ['https://live-api.liangle.com/1/7.5.60/live/queryLiveTextList', {}]
};
function apiURL(kind, matchId, key) {
  if (!ENDPOINTS[kind]) throw new Error('未知赛事请求');
  const [base, params] = ENDPOINTS[kind];
  const url = new URL(base); Object.entries(params).forEach(([k, v]) => url.searchParams.set(k, v));
  if (kind !== 'schedule') url.searchParams.set('matchId', matchId);
  if (kind === 'text') url.searchParams.set('liveActivityKeyStr', key);
  return url;
}
class LiveAPI {
  constructor(fetcher = fetch) { this.fetcher = fetcher; }
  async get(kind, matchId, key, signal) {
    const timeout = AbortSignal.timeout(12000);
    const response = await this.fetcher(apiURL(kind, matchId, key), { headers: { Accept: 'application/json' }, cache: 'no-store', redirect: 'error', signal: signal ? AbortSignal.any([timeout, signal]) : timeout });
    if (!response.ok) throw new Error(`赛事服务暂不可用（HTTP ${response.status}）`);
    const body = await response.text();
    if (body.length > 8 * 1024 * 1024) throw new Error('赛事响应超出大小限制');
    return decode(body);
  }
  async schedule(signal) {
    const data = await this.get('schedule', undefined, undefined, signal);
    if (!Array.isArray(data.gameList)) throw new Error('赛事服务返回的赛程无效');
    return { days: data.gameList.map(d => ({ day: String(d.day), dayBlock: d.dayBlock || String(d.day), matchList: (d.matchList || []).map(normalizeMatch) })), currentDate: data.scheduleListStats?.currentDate };
  }
  async match(id, signal) { return normalizeMatch(await this.get('match', id, undefined, signal)); }
  async key(id, signal) { const k = (await this.get('key', id, undefined, signal)).liveActivityKey; if (typeof k !== 'string' || !k) throw new Error('直播参数无效'); return k; }
  async text(id, key, signal) { return normalizeEntries(await this.get('text', id, key, signal)); }
}
function cleanPreferences(input = {}) {
  const p = { ...DEFAULTS };
  for (const k of ['pinned', 'simple', 'scoreOnly', 'menuScore']) if (typeof input[k] === 'boolean') p[k] = input[k];
  if (['system', 'light', 'dark'].includes(input.theme)) p.theme = input.theme;
  if (Number.isInteger(input.rows)) p.rows = Math.max(1, Math.min(6, input.rows));
  if (typeof input.shortcut === 'string' && input.shortcut.length < 80 && /(?:Control|Alt|Command|Super)\+/.test(input.shortcut)) p.shortcut = input.shortcut;
  p.favorites = Array.isArray(input.favorites) ? [...new Set(input.favorites.filter(v => typeof v === 'string' && v.length < 40))].slice(0, 60) : [];
  if (typeof input.lastMatch === 'string' && input.lastMatch.length < 100) p.lastMatch = input.lastMatch;
  return p;
}
class LiveController extends EventEmitter {
  constructor(api, preferences = {}, persist = () => {}) {
    super(); this.api = api; this.persist = persist;
    this.state = { days: [], selectedDay: '', teamFilter: '全部球队', selectedMatch: null, entries: [], frozenEntries: [], following: true, unread: 0, loadingSchedule: false, loadingLive: false, scheduleError: '', matchError: '', textError: '', scoreUpdatedAt: null, textUpdatedAt: null, page: 'matches', compact: false, hovered: false, menuOpen: false, shortcutError: '', preferences: cleanPreferences(preferences), demo: false };
    this.state.compact = this.state.preferences.simple;
    this.generation = 0; this.scheduleGeneration = 0; this.stopped = false;
  }
  publish() { this.emit('change', this.state); }
  setPreferences(patch) { this.state.preferences = cleanPreferences({ ...this.state.preferences, ...patch }); this.persist(this.state.preferences); this.publish(); }
  async start() { this.stopped = false; await this.refreshSchedule(true); if (!this.stopped) this.scheduleTimer = setInterval(() => void this.refreshSchedule(), 60000); }
  stop() { this.stopped = true; clearTimeout(this.timer); clearInterval(this.scheduleTimer); this.abort?.abort(); this.scheduleAbort?.abort(); }
  async refreshSchedule(restore = false) {
    if (this.state.demo) return;
    const generation = ++this.scheduleGeneration; this.scheduleAbort?.abort(); this.scheduleAbort = new AbortController();
    this.state.loadingSchedule = true; this.publish();
    try {
      const { days, currentDate } = await this.api.schedule(this.scheduleAbort.signal);
      if (this.stopped || generation !== this.scheduleGeneration) return;
      this.state.days = days;
      if (!days.some(d => d.day === this.state.selectedDay)) this.state.selectedDay = days.find(d => d.day === currentDate)?.day || days[0]?.day || '';
      this.state.scheduleError = '';
      if (restore) { const saved = days.flatMap(d => d.matchList).find(m => m.matchId === this.state.preferences.lastMatch); if (saved) this.select(saved); }
    } catch (e) { if (!this.stopped && generation === this.scheduleGeneration) this.state.scheduleError = e.message; }
    finally { if (generation === this.scheduleGeneration) { this.state.loadingSchedule = false; this.publish(); } }
  }
  switchableMatches() {
    const favorites = this.state.preferences.favorites;
    return [...(this.state.days.find(d => d.day === this.state.selectedDay)?.matchList || [])].sort((a, b) => {
      const f = m => favorites.includes(m.homeTeamName) || favorites.includes(m.awayTeamName);
      return Number(f(b)) - Number(f(a)) || Number(isLive(b)) - Number(isLive(a)) || String(a.matchTime || '').localeCompare(String(b.matchTime || ''));
    });
  }
  select(match) {
    if (this.state.selectedMatch?.matchId === match.matchId) { this.state.page = 'live'; this.publish(); return; }
    this.abort?.abort(); clearTimeout(this.timer); const generation = ++this.generation;
    Object.assign(this.state, { selectedMatch: match, page: 'live', entries: [], frozenEntries: [], following: true, unread: 0, loadingLive: true, matchError: '', textError: '', scoreUpdatedAt: null, textUpdatedAt: null });
    this.key = null; this.failures = 0; this.lastScore = 0;
    this.setPreferences({ lastMatch: match.matchId });
    if (this.state.demo) { this.state.loadingLive = false; this.publish(); return; }
    this.abort = new AbortController(); void this.poll(generation, this.abort.signal);
  }
  async poll(generation, signal) {
    const current = () => !this.stopped && !signal.aborted && generation === this.generation;
    const id = this.state.selectedMatch.matchId;
    if (Date.now() - this.lastScore >= 9000) {
      try {
        const match = await this.api.match(id, signal); if (!current()) return;
        this.state.selectedMatch = match; this.state.scoreUpdatedAt = Date.now(); this.state.matchError = ''; this.lastScore = Date.now(); this.publish();
      } catch (e) { if (!current()) return; this.state.matchError = e.message; }
    }
    if (!current()) return;
    if (isUpcoming(this.state.selectedMatch)) this.state.textError = '';
    else if (this.state.selectedMatch.openLive === false) this.state.textError = '本场暂未提供文字直播';
    else {
      try {
        const key = this.key || await this.api.key(id, signal); if (!current()) return; this.key = key;
        const entries = await this.api.text(id, key, signal); if (!current()) return;
        const known = new Set(this.state.entries.map(e => e.id));
        if (!this.state.following) this.state.unread += new Set(entries.filter(e => !known.has(e.id)).map(e => e.id)).size;
        this.state.entries = mergeEntries(entries, this.state.entries); this.state.textError = ''; this.state.textUpdatedAt = Date.now();
      } catch (e) { if (!current()) return; this.state.textError = e.message; this.key = null; }
    }
    if (!current()) return;
    this.state.loadingLive = false;
    this.failures = this.state.matchError || (this.state.textError && this.state.selectedMatch.openLive !== false) ? (this.failures || 0) + 1 : 0;
    this.publish();
    if (isFinished(this.state.selectedMatch) && this.failures === 0) return;
    const wait = this.failures ? Math.min(60000, 5000 * 2 ** Math.min(this.failures, 4)) : isUpcoming(this.state.selectedMatch) ? 30000 : 5000;
    this.timer = setTimeout(() => void this.poll(generation, signal), wait);
  }
  retry() {
    if (this.state.demo || !this.state.selectedMatch) return;
    this.abort?.abort(); clearTimeout(this.timer); this.abort = new AbortController(); this.key = null; this.lastScore = 0; this.failures = 0;
    void this.poll(++this.generation, this.abort.signal);
  }
  toggleFollowing() {
    this.state.following = !this.state.following;
    this.state.frozenEntries = this.state.following ? [] : [...this.state.entries];
    if (this.state.following) this.state.unread = 0;
    this.publish();
  }
  loadDemo() {
    this.state.demo = true;
    const match = { matchId: 'demo', matchStatus: 'INPROGRESS', awayTeamName: '湖人', homeTeamName: '勇士', awayScore: 102, homeScore: 99, openLive: true, frontEndMatchStatus: { desc: '第四节 剩2:18' } };
    this.state.days = [{ day: 'demo', dayBlock: '演示比赛日', matchList: [match, { ...match, matchId: 'demo-2', awayTeamName: '76人', homeTeamName: '尼克斯', awayScore: 106, homeScore: 100, matchStatus: 'COMPLETED', frontEndMatchStatus: { desc: '已结束' } }, { ...match, matchId: 'demo-3', awayTeamName: '雷霆', homeTeamName: '马刺', matchStatus: 'NOTSTARTED', matchTime: '2026-10-21 11:00:00', frontEndMatchStatus: null }] }];
    Object.assign(this.state, { selectedDay: 'demo', selectedMatch: match, page: 'live', scoreUpdatedAt: Date.now(), textUpdatedAt: Date.now(), entries: ['詹姆斯突破上篮得分，湖人领先三分。', '库里借掩护三分出手，球弹筐而出。', '湖人拿下防守篮板，准备发动反击。', '暂停结束，比赛继续。'].map((content, i) => ({ id: `demo-${i}`, content, time: `2026-10-21 10:18:${32 - i * 5}`, nickName: '演示解说' })) });
    this.publish();
  }
}
module.exports = { DEFAULTS, LiveAPI, LiveController, cleanPreferences, normalizeMatch, normalizeEntries, decode, apiURL, plainText, mergeEntries, score, status, heading, isLive, isUpcoming, isFinished };
