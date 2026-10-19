import DOMPurify from 'dompurify';
import { sb, content, status, setup, el, button } from './viewer-ui.mjs';

export function resolvePath(href, base) {
  try {
    const path = decodeURIComponent(href.split('#')[0].split('?')[0]);
    if (/^(?:[a-z][a-z0-9+.-]*:|\/)/i.test(path) || /[\\\0]/.test(path)) return null;
    if (!path) return base;
    const parts = base.split('/').slice(0,-1);
    for (const part of path.split('/')) {
      if (part === '..') { if (!parts.length) return null; parts.pop(); }
      else if (part && part !== '.') parts.push(part);
    }
    return parts.join('/');
  } catch (_) { return null; }
}
const raster = value => typeof value === 'string' && /^data:image\/(png|jpeg|gif|webp);base64,[a-z0-9+/=\s]+$/i.test(value);

try {
  const data = sb.data;
  if (!data || !Array.isArray(data.chapters) || !data.chapters.length) throw Error('This book has no readable excerpt');
  setup([data.authors?.join(', '), data.language, `${data.totalChapters} sections`].filter(Boolean).join(' · '));
  const sidebar = document.getElementById('sidebar'); sidebar.hidden = false; sidebar.append(el('h2', '', 'Contents'));
  const reader = el('article', 'reader'); content.append(reader);
  const tocButtons = [];
  for (const entry of data.toc || []) {
    const index = data.chapters.findIndex(chapter => chapter.path === entry.path);
    const item = button(entry.title || 'Untitled section', () => show(index));
    item.disabled = index < 0;
    if (index < 0) item.title = 'Outside this preview excerpt';
    sidebar.append(item); tocButtons.push({ item, index });
  }
  function show(index) {
    if (index < 0 || index >= data.chapters.length) return;
    const chapter = data.chapters[index];
    const fragment = DOMPurify.sanitize(chapter.html, {
      USE_PROFILES: { html: true }, RETURN_DOM_FRAGMENT: true,
      FORBID_TAGS: ['style','link','form','input','button','textarea','audio','video','source'],
      FORBID_ATTR: ['style','id','name','srcset','action','formaction','ping','background']
    });
    for (const image of fragment.querySelectorAll('img')) {
      const path = resolvePath(image.getAttribute('src') || '', chapter.path);
      const resource = path && Object.hasOwn(data.resources || {}, path) ? data.resources[path] : null;
      if (raster(resource)) image.setAttribute('src', resource);
      else image.replaceWith(el('span', 'notice', image.alt ? `[Image: ${image.alt}]` : '[Image unavailable in this excerpt]'));
    }
    for (const link of fragment.querySelectorAll('a')) {
      const path = resolvePath(link.getAttribute('href') || '', chapter.path);
      const target = data.chapters.findIndex(item => item.path === path);
      link.removeAttribute('href'); link.removeAttribute('target');
      if (target >= 0 && target !== index) {
        link.href = '#'; link.addEventListener('click', event => { event.preventDefault(); show(target); });
      }
    }
    reader.replaceChildren();
    if (raster(data.cover)) { const cover = el('img', 'cover'); cover.src = data.cover; cover.alt = 'Book cover'; reader.append(cover); }
    reader.append(el('h1', 'book-title', data.title), el('p', 'book-author', data.authors?.join(', ') || ''));
    const body = el('div', 'book-body'); body.append(fragment); reader.append(body);
    for (const entry of tocButtons) entry.item.setAttribute('aria-current', String(entry.index === index));
    status.textContent = `${chapter.title} · ${index + 1} of ${data.chapters.length} preview sections${data.truncated ? ` · Excerpt from ${data.totalChapters} sections; some content may be omitted` : ''}`;
    content.scrollTop = 0;
  }
  show(0); sb.done();
} catch (error) { sb.fail(error.message); }
