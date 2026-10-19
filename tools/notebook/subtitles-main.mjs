import DOMPurify from 'dompurify';
import { parseSubtitles, timeLabel, cueText } from './subtitles-model.mjs';
import { sb, content, actions, status, setup, el, button, search } from './viewer-ui.mjs';

try {
  if (typeof sb.data !== 'string') throw Error('Expected subtitle text');
  const data = parseSubtitles(sb.data);
  const plain = source => {
    // Preserve speaker labels while dropping WebVTT timestamp/class annotations.
    const voices = source.replace(/<v(?:\.[^ >]+)*\s+([^>]+)>/g, (_, voice) => `${voice}: `).replace(/<\/?(?:c(?:\.[^ >]+)*|v|lang(?:\s+[^>]+)?|\d{2}:\d{2}[^>]*)>/g, '');
    return DOMPurify.sanitize(voices, { ALLOWED_TAGS: ['b','i','u','ruby','rt','br'], ALLOWED_ATTR: [] });
  };
  for (const cue of data.cues) {
    // Search uses decoded text, so entities and subtitle markup don't interfere.
    cue.text = cueText(cue.source).toLocaleLowerCase();
  }
  setup(`${data.format} · ${data.cues.length.toLocaleString()} cues · ends at ${timeLabel(data.duration)}`);
  let filtered = data.cues, shown = 0;
  const list = el('div', 'cues'), empty = el('p', 'empty'), more = button('Show more cues', () => page()); more.className = 'paging';
  content.append(list, empty, more);
  actions.append(search('Search dialogue', value => { const q = value.trim().toLocaleLowerCase(); filtered = data.cues.filter(c => c.text.includes(q) || c.id.toLocaleLowerCase().includes(q)); reset(); }));
  const toggle = button('Transcript', () => { const enabled = list.classList.toggle('transcript'); toggle.textContent = enabled ? 'Timestamps' : 'Transcript'; toggle.setAttribute('aria-pressed', String(enabled)); });
  toggle.setAttribute('aria-pressed', 'false'); actions.append(toggle);
  function page() {
    const end = Math.min(shown + 200, filtered.length);
    for (; shown < end; shown++) {
      const cue = filtered[shown], row = el('section', 'cue'), time = el('div', 'cue-time');
      time.append(el('div', '', timeLabel(cue.start)), el('div', '', `→ ${timeLabel(cue.end)}`));
      if (cue.id) time.append(el('div', 'cue-id', cue.id));
      const body = el('div', 'cue-text'); body.innerHTML = cue.html ??= plain(cue.source);
      if (cue.truncated) body.append(el('p', 'notice', 'Long cue truncated.'));
      row.append(time, body); list.append(row);
    }
    more.hidden = shown >= filtered.length;
    status.textContent = `${shown.toLocaleString()} of ${filtered.length.toLocaleString()} cues${data.invalid ? ` · ${data.invalid} malformed blocks skipped` : ''}${data.truncated ? ' · Preview limit reached' : ''}`;
  }
  function reset() { shown = 0; list.replaceChildren(); page(); empty.hidden = filtered.length > 0; empty.textContent = data.cues.length ? 'No matching dialogue.' : 'This subtitle file has no cues.'; content.scrollTop = 0; }
  reset(); sb.done();
} catch (error) { sb.fail(error.message); }
