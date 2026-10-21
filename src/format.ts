import type { Match } from './types';
export const isLive = (m: Match) => m.matchStatus === 'INPROGRESS';
export const isUpcoming = (m: Match) => m.matchStatus === 'NOTSTARTED';
export const score = (m: Match) => isUpcoming(m) ? 'vs' : `${m.awayScore ?? '—'} : ${m.homeScore ?? '—'}`;
export const status = (m: Match) => m.frontEndMatchStatus?.desc || (isLive(m) ? '进行中' : m.matchStatus === 'COMPLETED' ? '已结束' : isUpcoming(m) ? '未开始' : '赛程待定');
export const startLabel = (m: Match) => m.matchTime?.slice(5, 16) || '时间待定';
export const clock = (time: string) => time.length >= 19 ? time.slice(-8) : time;
