import DOMPurify from 'dompurify';
import { parseSubtitles, timeLabel } from './subtitles-model.mjs';
import { sb, content, status, setup, el, button } from './viewer-ui.mjs';

try {
  if (typeof sb.data !== 'string') throw Error('Expected subtitle text');
  const data = parseSubtitles(sb.data);
  const plain = source => {
    // Preserve speaker labels while dropping WebVTT timestamp/class annotations.
    const voices = source.replace(/<v(?:\.[^ >]+)*\s+([^>]+)>/g, (_, voice) => `${voice}: `).replace(/<\/?(?:c(?:\.[^ >]+)*|v|lang(?:\s+[^>]+)?|\d{2}:\d{2}[^>]*)>/g, '');
    return DOMPurify.sanitize(voices, { ALLOWED_TAGS: ['b','i','u','ruby','rt','br'], ALLOWED_ATTR: [] });
  };
  setup(`${data.format} · ${data.cues.length.toLocaleString()} cues · ends at ${timeLabel(data.duration)}`);
  let shown = 0;
  const list = el('div', 'cues'), empty = el('p', 'empty'), more = button('Show more cues', () => page()); more.className = 'paging';
  content.append(list, empty, more);
  function page() {
    const end = Math.min(shown + 200, data.cues.length);
    for (; shown < end; shown++) {
      const cue = data.cues[shown], row = el('section', 'cue'), time = el('div', 'cue-time');
      time.append(el('div', '', timeLabel(cue.start)), el('div', '', `→ ${timeLabel(cue.end)}`));
      if (cue.id) time.append(el('div', 'cue-id', cue.id));
      const body = el('div', 'cue-text'); body.innerHTML = cue.html ??= plain(cue.source);
      if (cue.truncated) body.append(el('p', 'notice', 'Long cue truncated.'));
      row.append(time, body); list.append(row);
    }
    more.hidden = shown >= data.cues.length;
    status.textContent = `${shown.toLocaleString()} of ${data.cues.length.toLocaleString()} cues${data.invalid ? ` · ${data.invalid} malformed blocks skipped` : ''}${data.truncated ? ' · Preview limit reached' : ''}`;
  }
  empty.hidden = data.cues.length > 0; empty.textContent = 'This subtitle file has no cues.';
  page(); sb.done();
} catch (error) { sb.fail(error.message); }
