import { sb, content, status, setup, el, button, size } from './viewer-ui.mjs';

try {
  const data = sb.data;
  if (!data || !Array.isArray(data.entries)) throw Error('Expected an archive listing');
  const root = { path: '', children: new Map() };
  const rows = [];
  for (const entry of data.entries) {
    const raw = String(entry.path);
    const parts = raw.replace(/^(?:\.\/)+/, '').split('/').filter(Boolean);
    // Unusual paths remain literal entries; they are never filesystem paths.
    if (!parts.length) continue;
    if (entry.unsafePath || parts.length > 64) { rows.push({ ...entry, unsafePath: true, path: raw, name: raw }); continue; }
    let parent = root;
    for (let i = 0; i < parts.length; i++) {
      const path = parts.slice(0, i + 1).join('/');
      if (!parent.children.has(parts[i])) parent.children.set(parts[i], { name: parts[i], path, kind: 'directory', size: 0, children: new Map() });
      const node = parent.children.get(parts[i]);
      if (i === parts.length - 1) Object.assign(node, entry, { name: parts[i], path });
      parent = node;
    }
  }
  const collect = node => { for (const child of node.children.values()) { rows.push(child); collect(child); } };
  collect(root);
  const folders = new Map(rows.filter(r => r.kind === 'directory').map(r => [r.path, r])); folders.set('', root);
  let current = root, visible = [], shown = 0;
  setup(`${data.format || 'Archive'} · ${data.entries.length.toLocaleString()}${data.truncated ? '+' : ''} entries`);
  const breadcrumbs = el('nav', 'breadcrumbs'); breadcrumbs.setAttribute('aria-label', 'Archive folders');
  const table = el('table'); const thead = el('thead'); const heading = el('tr');
  heading.append(el('th', '', 'Name'), el('th', '', 'Kind'), el('th', 'size', 'Size'), el('th', '', 'Modified')); thead.append(heading);
  const tbody = el('tbody'); table.append(thead, tbody);
  const more = button('Show more', () => page()); more.className = 'paging';
  const empty = el('p', 'empty');
  content.append(breadcrumbs, table, empty, more);
  function navigate(folder) { current = folder; refresh(); }
  function pathLink(label, folder) {
    const link = el('a', '', label); link.href = '#';
    link.addEventListener('click', event => { event.preventDefault(); navigate(folder); });
    if (folder === current) link.setAttribute('aria-current', 'location');
    return link;
  }
  function page() {
    const end = Math.min(shown + 200, visible.length);
    for (; shown < end; shown++) {
      const row = visible[shown], tr = el('tr'), name = el('td', 'entry-path');
      if (row.kind === 'directory') name.append(button(`▸ ${row.name}`, () => navigate(row)));
      else name.append(el('span', '', row.name));
      name.querySelector('button')?.classList.add('entry-name');
      if (row.encrypted) name.append(el('span', 'badge', 'Encrypted'));
      if (row.unsafePath) name.append(el('span', 'badge', 'Unusual path'));
      if (row.target) name.append(el('span', 'badge', `→ ${row.target}`));
      tr.append(name, el('td', 'entry-kind', row.kind), el('td', 'size', row.kind === 'directory' ? '—' : size(row.size)), el('td', 'time', row.modified ? String(row.modified).slice(0, 10) : '—'));
      tbody.append(tr);
    }
    more.hidden = shown >= visible.length;
    status.textContent = `${shown.toLocaleString()} of ${visible.length.toLocaleString()} entries${data.truncated ? ' · Partial archive listing' : ''}`;
  }
  function refresh() {
    visible = [...current.children.values(), ...(current === root ? rows.filter(r => r.unsafePath) : [])];
    visible.sort((a,b) => (a.kind === 'directory' ? 0 : 1) - (b.kind === 'directory' ? 0 : 1) || a.name.localeCompare(b.name, undefined, { numeric: true }));
    breadcrumbs.replaceChildren(pathLink('Archive', root));
    const parts = current.path.split('/').filter(Boolean);
    parts.forEach((part,i) => {
      const separator = el('span', 'path-separator', ' > '); separator.setAttribute('aria-hidden', 'true');
      breadcrumbs.append(separator, pathLink(part, folders.get(parts.slice(0,i+1).join('/')) || root));
    });
    tbody.replaceChildren(); shown = 0; page();
    empty.hidden = visible.length > 0; empty.textContent = 'This folder is empty.';
    content.scrollTop = 0;
  }
  refresh();
  for (const warning of data.warnings || []) content.prepend(el('p', 'notice', warning));
  sb.done();
} catch (error) { sb.fail(error.message); }
