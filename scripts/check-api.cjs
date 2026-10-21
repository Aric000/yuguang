const { LiveAPI, heading, isLive, isFinished } = require('../desktop/core.cjs');
(async () => {
  const api = new LiveAPI(); const { days } = await api.schedule(); const matches = days.flatMap(d=>d.matchList);
  console.log(`赛程：${days.length} 天，${matches.length} 场`);
  const match = matches.find(isLive) || matches.find(isFinished);
  if (!match) throw new Error('暂无可验证的比赛');
  const [detail,key] = await Promise.all([api.match(match.matchId),api.key(match.matchId)]);
  const entries = await api.text(match.matchId,key);
  console.log(`比赛：${heading(detail)}`); console.log(`文字：${entries.length} 条；最新：${entries[0]?.content || '暂无'}`);
})().catch(e=>{ console.error(e); process.exitCode=1; });
