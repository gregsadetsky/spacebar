import { renderHTML, renderMarkdown, renderImage, renderSVG, renderText, renderLatex } from '@jupyterlab/rendermime/lib/renderers.js';
import DOMPurify from 'dompurify';
import { marked } from 'marked';
import renderMath from 'katex/contrib/auto-render';
import hljs from 'highlight.js/lib/core';
import python from 'highlight.js/lib/languages/python';
import javascript from 'highlight.js/lib/languages/javascript';
import typescript from 'highlight.js/lib/languages/typescript';
import r from 'highlight.js/lib/languages/r';
import julia from 'highlight.js/lib/languages/julia';
import bash from 'highlight.js/lib/languages/bash';
import sql from 'highlight.js/lib/languages/sql';
import json from 'highlight.js/lib/languages/json';
import { bundle, limits, text } from './model.mjs';

for (const [name, language] of Object.entries({ python, javascript, typescript, r, julia, bash, sql, json })) hljs.registerLanguage(name, language);

export function element(tag, className = '', content) {
  const node = document.createElement(tag);
  node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
}

export function notice(host, message) { host.append(element('p', 'notice', message)); }

function sanitizer(attachments = {}) {
  return {
    getAutolink: () => false,
    sanitize(source) {
      const fragment = DOMPurify.sanitize(source, {
        USE_PROFILES: { html: true }, RETURN_DOM_FRAGMENT: true,
        FORBID_TAGS: ['style', 'form', 'input', 'button', 'textarea', 'audio', 'video', 'source'],
        FORBID_ATTR: ['style', 'srcset', 'id', 'name', 'action', 'formaction', 'ping', 'background'],
        ALLOWED_URI_REGEXP: /^(?:#|attachment:|data:image\/(?:png|jpeg|gif|webp);base64,)/i
      });
      for (const image of fragment.querySelectorAll('img')) {
        let src = image.getAttribute('src') || '';
        if (src.startsWith('attachment:')) {
          let name = src.slice(11);
          try { name = decodeURIComponent(name); } catch (_) { /* literal attachment name */ }
          const data = Object.hasOwn(attachments, name) ? bundle(attachments[name]) : {};
          const mime = ['image/png', 'image/jpeg', 'image/gif', 'image/webp'].find(type => data[type]);
          src = mime && data[mime].length <= limits.image ? `data:${mime};base64,${data[mime]}` : '';
        }
        if (!/^data:image\/(png|jpeg|gif|webp);base64,[a-z0-9+/=\s]+$/i.test(src) || src.length > limits.image) {
          image.replaceWith(element('span', 'notice', image.alt ? `[Image: ${image.alt}]` : '[Image unavailable offline]'));
        } else { image.setAttribute('src', src); }
      }
      for (const link of fragment.querySelectorAll('a[href]')) {
        if (!link.getAttribute('href').startsWith('#')) link.removeAttribute('href');
      }
      const container = document.createElement('div');
      container.append(fragment);
      return container.innerHTML;
    }
  };
}

function staticSVG(source) {
  const fragment = DOMPurify.sanitize(source, {
    USE_PROFILES: { svg: true, svgFilters: true }, RETURN_DOM_FRAGMENT: true,
    FORBID_TAGS: ['script', 'foreignObject', 'image', 'feImage', 'animate', 'animateMotion', 'animateTransform', 'set', 'style']
  });
  // Preserve geometry, colors and local clip-path references. A URI allowlist
  // passed to DOMPurify would also strip ordinary SVG presentation attributes.
  for (const node of fragment.querySelectorAll('*')) {
    // Matplotlib writes strokes and fills as inline CSS. Keep only static SVG
    // presentation properties, converting them to attributes before discarding CSS.
    for (const property of ['fill', 'fill-opacity', 'stroke', 'stroke-width', 'stroke-opacity',
      'stroke-dasharray', 'stroke-dashoffset', 'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit',
      'opacity', 'font-family', 'font-size', 'font-style', 'font-weight', 'text-anchor',
      'dominant-baseline', 'clip-path', 'display', 'visibility']) {
      const value = node.style?.getPropertyValue(property);
      if (value) node.setAttribute(property, value);
    }
    node.removeAttribute('style');
    for (const attr of [...node.attributes]) {
      const value = attr.value;
      if ((attr.localName === 'href' && !value.startsWith('#')) || value.includes('\\') ||
          (/url\s*\(/i.test(value) && !/^url\(\s*(['"]?)#[\w:.-]+\1\s*\)$/i.test(value))) {
        node.removeAttributeNode(attr);
      }
    }
  }
  const container = document.createElement('div');
  container.append(fragment);
  return container.innerHTML;
}

const latexTypesetter = {
  typeset(host) {
    renderMath(host, {
      delimiters: [{ left: '$$', right: '$$', display: true }, { left: '\\[', right: '\\]', display: true },
        { left: '\\(', right: '\\)', display: false }, { left: '$', right: '$', display: false }],
      throwOnError: false, trust: false, strict: 'ignore', maxExpand: 1000,
      errorCallback: () => {}
    });
  }
};

function options(host, source, attachments) {
  return { host, source, trusted: false, sanitizer: sanitizer(attachments),
    resolver: null, linkHandler: null, shouldTypeset: true, latexTypesetter,
    markdownParser: { render: value => marked.parse(value, { gfm: true, async: false }) } };
}

export function code(host, source, language) {
  const pre = element('pre');
  const node = element('code', 'hljs');
  const value = source.slice(0, limits.text);
  if (hljs.getLanguage(language)) node.innerHTML = hljs.highlight(value, { language, ignoreIllegals: true }).value;
  else node.textContent = value;
  pre.append(node); host.append(pre);
  if (source.length > limits.text) notice(host, 'Code truncated after 100,000 characters.');
}

export async function markdown(host, source, attachments) {
  await renderMarkdown(options(host, source.slice(0, limits.text), attachments));
  for (const block of host.querySelectorAll('pre code')) {
    const language = Array.from(block.classList).find(name => name.startsWith('language-'))?.slice(9);
    if (language && hljs.getLanguage(language)) block.innerHTML = hljs.highlight(block.textContent, { language, ignoreIllegals: true }).value;
  }
  if (source.length > limits.text) notice(host, 'Markdown truncated after 100,000 characters.');
}

async function plain(host, source) {
  await renderText(options(host, source.slice(0, limits.text)));
  if (source.length > limits.text) notice(host, 'Output truncated after 100,000 characters.');
}

export async function output(host, value) {
  if (!value || typeof value !== 'object') { notice(host, 'Invalid saved output.'); return; }
  if (value.output_type === 'stream') {
    if (value.name === 'stderr') host.classList.add('stderr');
    await plain(host, text(value.text)); return;
  }
  if (value.output_type === 'error') {
    host.classList.add('error');
    const traceback = Array.isArray(value.traceback) ? value.traceback.filter(line => typeof line === 'string').join('\n') : '';
    await plain(host, traceback || `${text(value.ename)}: ${text(value.evalue)}`); return;
  }
  const data = bundle(value.data);
  const types = ['text/html', 'image/png', 'image/jpeg', 'image/svg+xml', 'image/gif', 'image/webp', 'text/markdown', 'text/latex', 'text/plain', 'application/json'];
  const mime = types.find(type => Object.hasOwn(data, type));
  if (!mime) { notice(host, 'This output has no static preview (for example, an interactive widget).'); return; }
  if (mime.startsWith('image/')) {
    const source = data[mime];
    if (source.length > limits.image) {
      notice(host, 'Image exceeds the preview limit.');
      if (data['text/plain']) await plain(host, data['text/plain']);
      return;
    }
    if (mime === 'image/svg+xml') {
      // The sanitized SVG is displayed as an image, never inserted as active markup.
      const clean = staticSVG(source);
      await renderSVG({ host, source: clean, trusted: true });
    } else {
      if (!/^[a-z0-9+/=\s]+$/i.test(source)) { notice(host, 'Invalid saved image.'); return; }
      const metadata = value.metadata?.[mime];
      await renderImage({ host, source, mimeType: mime,
        width: Number.isFinite(metadata?.width) && metadata.width > 0 ? Math.min(metadata.width, 4096) : undefined,
        height: Number.isFinite(metadata?.height) && metadata.height > 0 ? Math.min(metadata.height, 4096) : undefined });
    }
    host.querySelector('img')?.setAttribute('alt', 'Saved notebook output');
  } else if (mime === 'text/html') {
    // Sanitizing a truncated HTML fragment would produce a misleading partial table.
    if (data[mime].length > limits.text) {
      notice(host, 'HTML output exceeds the preview limit.');
      if (data['text/plain']) await plain(host, data['text/plain']);
    } else {
      await renderHTML(options(host, data[mime]));
      if (!host.textContent.trim() && !host.querySelector('img, table, hr')) {
        if (data['text/plain']) await plain(host, data['text/plain']);
        else notice(host, 'This HTML output has no static preview.');
      }
    }
  } else if (mime === 'text/markdown') {
    await markdown(host, data[mime]);
  } else if (mime === 'text/latex') {
    // renderLatex assigns textContent before typesetting.
    await renderLatex({ host, source: data[mime].slice(0, limits.text), shouldTypeset: true, latexTypesetter });
  } else {
    await plain(host, mime === 'application/json' ? JSON.stringify(data[mime], null, 2) : data[mime]);
  }
}
