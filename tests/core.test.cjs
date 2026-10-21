const { test } = require('node:test');
const assert = require('node:assert/strict');
const { decode, normalizeMatch, normalizeEntries, mergeEntries, apiURL, cleanPreferences, LiveController, heading, score } = require('../desktop/core.cjs');
const { clampBounds, snapBounds } = require('../desktop/geometry.cjs');
const match = (id, extra = {}) => ({ matchId: id, homeTeamName: '勇士', awayTeamName: '湖人', matchStatus: 'INPROGRESS', homeScore: 99, awayScore: 102, ...extra });
const settle = () => new Promise(resolve => setImmediate(resolve));
test('large integer IDs remain exact strings', () => {
  const data = decode('{"result":{"matchId":1537445624050352128,"homeTeamName":"勇士","awayTeamName":"湖人","matchStatus":"INPROGRESS"}}');
  assert.equal(normalizeMatch(data).matchId, '1537445624050352128');
});
test('business errors survive a differently shaped result', () => { assert.throws(() => decode('{"status":403,"success":false,"msg":"直播参数已过期","result":{"reason":"expired"}}'), /直播参数已过期/); });
test('missing results and prototype pollution are rejected', () => { assert.throws(() => decode('{"result":null}')); assert.throws(() => decode('{"result":{"__proto__":{"polluted":true}}}')); });
test('zero scores are shown and upcoming scores do not invent zeros', () => { assert.equal(score(match('1',{ awayScore: 0, homeScore: null })), '0 : —'); assert.equal(score(match('1',{ matchStatus:'NOTSTARTED' })), 'vs'); });
test('tray heading includes the live score and status', () => { assert.equal(heading(match('1')), '湖人 102 : 99 勇士 · 进行中'); });
test('room key is encoded exactly once', () => { const key = '79668677:1495229:1034001&x=+/?'; const url = apiURL('text','123',key); assert.equal(url.searchParams.get('liveActivityKeyStr'), key); assert.equal([...url.searchParams].length, 2); });
test('messages are plain text and IDs preserve service order', () => {
  const entries = normalizeEntries([{ commentId: '2', content:'<b>三分</b><br/>命中 &amp; 得分' },{ commentId:'99', content:'下一条' }]);
  assert.equal(entries[0].content,'三分 命中 & 得分');
  const merged = mergeEntries(entries,[{ id:'99',content:'旧内容' },{ id:'30',content:'历史' }]);
  assert.deepEqual(merged.map(e => e.id),['2','99','30']); assert.equal(mergeEntries(entries,merged,1).length,1);
});
test('preferences clamp row counts and discard untrusted fields', () => { const p = cleanPreferences({ rows:999, theme:'remote', favorites:['湖人','湖人',null], shortcut:'x', pinned:'true', injected:1 }); assert.equal(p.rows,6); assert.equal(p.theme,'system'); assert.equal(p.shortcut,'Control+`'); assert.equal(p.pinned,true); assert.deepEqual(p.favorites,['湖人']); assert.equal(p.injected,undefined); });
test('old match responses cannot overwrite newly selected match', async () => {
  let resolveOld;
  const api = { match: id => id === 'old' ? new Promise(resolve => { resolveOld = resolve; }) : Promise.resolve(match(id)), key: async () => 'room', text: async id => [{ id,content:id,time:'' }] };
  const c = new LiveController(api); c.select(match('old')); c.select(match('new')); await settle();
  resolveOld(match('old',{ homeScore:1 })); await settle();
  assert.equal(c.state.selectedMatch.matchId,'new'); assert.equal(c.state.entries[0].id,'new'); c.stop();
});
test('retry preserves last successful text if the network fails', async () => {
  const api = { match:async () => match('1'), key:async () => 'key', text:async () => { throw new Error('断网'); } };
  const c = new LiveController(api); c.state.selectedMatch=match('1'); c.state.entries=[{ id:'saved',content:'最后成功内容' }]; c.retry(); await settle();
  assert.equal(c.state.entries[0].id,'saved'); assert.equal(c.state.textError,'断网'); assert.ok(c.failures > 0); c.stop();
});
test('upcoming games poll score without fetching live text', async () => {
  let texts=0; const c=new LiveController({ match:async () => match('1',{ matchStatus:'NOTSTARTED' }), key:async () => 'key', text:async () => { texts++; return []; } });
  c.select(match('1')); await settle(); assert.equal(texts,0); assert.equal(c.state.loadingLive,false); c.stop();
});
test('completed games stop polling after the final successful request', async () => {
  const c=new LiveController({ match:async () => match('1',{ matchStatus:'COMPLETED' }), key:async () => 'key', text:async () => [] });
  c.select(match('1')); await settle(); assert.equal(c.timer,undefined); c.stop();
});
test('quick switching ignores the full-window team filter', () => { const c=new LiveController({}); c.loadDemo(); c.state.teamFilter='湖人'; assert.equal(c.switchableMatches().length,3); c.state.compact=true; c.select(c.switchableMatches()[1]); assert.equal(c.state.compact,true); c.stop(); });
test('history freezes while new text arrives and counts unique unseen entries', async () => {
  const c=new LiveController({ match:async () => match('1'), key:async () => 'key', text:async () => [{ id:'new',content:'新消息' },{ id:'new',content:'重复' }] });
  c.state.selectedMatch=match('1'); c.state.entries=[{ id:'old',content:'历史' }]; c.toggleFollowing(); c.retry(); await settle();
  assert.deepEqual(c.state.frozenEntries.map(e=>e.id),['old']); assert.equal(c.state.unread,1); c.toggleFollowing(); assert.equal(c.state.unread,0); c.stop();
});
test('window bounds recover when the saved monitor is removed', () => { assert.deepEqual(clampBounds({x:4000,y:2000,width:680,height:192},[{x:0,y:24,width:1440,height:876}]),{x:760,y:708,width:680,height:192}); });
test('edge snapping respects monitors with negative coordinates', () => { assert.equal(snapBounds({x:-1438,y:100,width:680,height:32},{x:-1440,y:0,width:1440,height:900}).x,-1432); });
