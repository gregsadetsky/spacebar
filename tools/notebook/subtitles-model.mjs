export function timestamp(value) {
  const match = /^(?:(\d{2,}):)?(\d{2}):(\d{2})[.,](\d{3})$/.exec(value);
  if (!match || Number(match[2]) > 59 || Number(match[3]) > 59) return null;
  const seconds = Number(match[1] || 0) * 3600 + Number(match[2]) * 60 + Number(match[3]) + Number(match[4]) / 1000;
  return Number.isFinite(seconds) ? seconds : null;
}
export function timeLabel(value) {
  const ms = Math.round(value * 1000), seconds = Math.floor(ms / 1000);
  return `${String(Math.floor(seconds / 3600)).padStart(2, '0')}:${String(Math.floor(seconds / 60) % 60).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}.${String(ms % 1000).padStart(3, '0')}`;
}
export function cueText(source) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', lrm: '\u200e', rlm: '\u200f' };
  return source.replace(/<v(?:\.[^ >]+)*\s+([^>]+)>/g, (_, voice) => `${voice}: `).replace(/<[^>]*>/g, '')
    .replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp|lrm|rlm);/gi, (original, code) => {
      if (!code.startsWith('#')) return entities[code.toLowerCase()] ?? original;
      const n = code[1].toLowerCase() === 'x' ? parseInt(code.slice(2), 16) : Number(code.slice(1));
      return n > 0 && n <= 0x10FFFF && !(n >= 0xD800 && n <= 0xDFFF) ? String.fromCodePoint(n) : '\uFFFD';
    });
}
export function parseSubtitles(source) {
  source = source.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  const vtt = /^WEBVTT(?:[ \t].*)?(?:\n|$)/.test(source);
  const cues = [];
  let invalid = 0, truncated = false;
  const blocks = source.split(/\n[ \t]*\n/);
  for (let block of blocks) {
    block = block.trim();
    if (!block || (vtt && /^(WEBVTT(?:[ \t\n]|$)|NOTE(?:[ \t\n]|$)|STYLE(?:[ \t\n]|$)|REGION(?:[ \t\n]|$))/.test(block))) continue;
    const lines = block.split('\n');
    const at = lines.findIndex((line, i) => i < 2 && line.includes('-->'));
    if (at < 0) { invalid++; continue; }
    const match = /^\s*(\S+)\s+-->\s+(\S+)(?:\s+.*)?$/.exec(lines[at]);
    const start = match ? timestamp(match[1]) : null, end = match ? timestamp(match[2]) : null;
    if (start === null || end === null || end < start) { invalid++; continue; }
    const body = lines.slice(at + 1).join('\n');
    cues.push({ id: at ? lines[0] : '', start, end, source: body.slice(0, 20_000), truncated: body.length > 20_000 });
    if (cues.length >= 30_000) { truncated = true; break; }
  }
  if (!cues.length && source.trim() && !(vtt && !invalid)) throw Error('No valid subtitle cues found');
  return { cues, format: vtt ? 'WebVTT' : 'SubRip', invalid, truncated, duration: cues.reduce((n, cue) => Math.max(n, cue.end), 0) };
}
