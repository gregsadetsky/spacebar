import { markdown } from './render.mjs';
import { sb, content, actions, status, setup, el, button, size } from './viewer-ui.mjs';

async function start() {
  if (typeof sb.data !== 'string') throw Error('Expected Markdown text');
  setup(`${size(sb.file.size)} · Markdown`);
  const source = sb.data.replace(/^\uFEFF/, '');
  const reader = el('article', 'reader');
  let body = source;
  const front = /^(---|\+\+\+)\r?\n([\s\S]*?)\r?\n\1(?:\r?\n|$)/.exec(source);
  if (front) {
    const details = el('details', 'frontmatter'); details.append(el('summary', '', 'Document metadata'), el('pre', '', front[2].slice(0, 100_000))); reader.append(details);
    body = source.slice(front[0].length);
  }
  const rendered = el('div', 'markdown'); reader.append(rendered);
  await markdown(rendered, body);
  // Stable local anchor targets and a short contents menu, without exposing
  // document-provided IDs to the surrounding viewer.
  const headings = [...rendered.querySelectorAll('h1,h2,h3')];
  for (const link of rendered.querySelectorAll('a[href^="#"]')) {
    let fragment;
    try { fragment = decodeURIComponent(link.getAttribute('href').slice(1)).toLowerCase(); } catch (_) { continue; }
    const target = headings.find(heading => (heading.dataset.jupyterId || '').toLowerCase() === fragment);
    if (target) link.addEventListener('click', event => { event.preventDefault(); target.scrollIntoView({ block: 'start' }); });
  }
  const sidebar = document.getElementById('sidebar');
  if (headings.length > 1) {
    sidebar.append(el('h2', '', 'Contents'));
    headings.slice(0, 150).forEach((heading, index) => {
      heading.id = `heading-${index}`;
      const title = heading.firstChild?.textContent || heading.textContent;
      sidebar.append(button(title.replace(/¶$/, ''), () => heading.scrollIntoView({ block: 'start' })));
    });
    actions.append(button('Contents', () => { sidebar.hidden = !sidebar.hidden; }));
  }
  const raw = el('pre', 'source-view', source.slice(0, 100_000)); raw.hidden = true;
  content.append(reader, raw);
  const toggle = button('Source', () => { raw.hidden = !raw.hidden; reader.hidden = !raw.hidden; toggle.textContent = raw.hidden ? 'Source' : 'Rendered'; if (!raw.hidden) sidebar.hidden = true; content.scrollTop = 0; });
  actions.append(toggle);
  if (!source.trim()) rendered.append(el('p', 'empty', 'This Markdown file is empty.'));
  status.textContent = source.length > 100_000 ? 'Preview limited to 100,000 characters.' : 'Markdown';
  sb.done();
}
start().catch(error => sb.fail(error.message));
