import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';
import { parseSubtitles, timestamp, cueText } from '../subtitles-model.mjs';

async function view(t, id, data) {
  const base = new URL(`../../../plugins/${id}/`, import.meta.url);
  const html = await readFile(new URL('index.html', base), 'utf8');
  const js = await readFile(new URL(`vendor/${id}.js`, base), 'utf8');
  const dom = new JSDOM(html, { runScripts: 'outside-only', pretendToBeVisual: true, url: 'https://spacebar.invalid/' });
  const w = dom.window, d = w.document;
  t.after(() => w.close());
  w.Element.prototype.scrollIntoView = function () { w.scrolled = this; };
  w.fetch = () => { throw Error('Unexpected network request'); };
  w.XMLHttpRequest = class { constructor() { throw Error('Unexpected XHR'); } };
  const outcome = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(Error('Viewer timed out')), 3000);
    const finish = message => { clearTimeout(timer); resolve(message); };
    w.spacebar = { data, theme: 'dark', file: { name: 'example', size: 200 }, done: () => finish('done'), fail: finish };
    try { w.eval(js); } catch (error) { clearTimeout(timer); reject(error); }
  });
  return { w, d, outcome };
}

test('Markdown renders metadata, math, code and tables, with source and contents controls', async t => {
  const { w, d, outcome } = await view(t, 'markdown', '---\ntitle: Example\n---\n# Hello\n\n[Jump](#Results)\n\n$E=mc^2$\n\n## Results\n\n```python\nprint(42)\n```\n\n| A | B |\n|---|---|\n| 1 | 2 |');
  assert.equal(outcome, 'done');
  assert.equal(d.documentElement.dataset.theme, 'dark');
  assert.match(d.querySelector('.frontmatter').textContent, /title: Example/);
  assert.ok(d.querySelector('.katex'));
  assert.ok(d.querySelector('.hljs-built_in'));
  assert.equal(d.querySelectorAll('td').length, 2);
  d.querySelector('.markdown a[href="#Results"]').click(); assert.match(w.scrolled.textContent, /Results/);
  d.querySelector('#sidebar button').click(); assert.ok(w.scrolled);
  [...d.querySelectorAll('#actions button')].find(b => b.textContent === 'Source').click();
  assert.equal(d.querySelector('.source-view').hidden, false);
  assert.match(d.querySelector('.source-view').textContent, /# Hello/);
});

test('Markdown removes active HTML and unavailable external images', async t => {
  const { w, d, outcome } = await view(t, 'markdown', '# Safe\n\n<script>window.attacked=1</script><img src="https://example.com/pixel" onerror="window.attacked=1"><iframe src="file:///etc/passwd"></iframe>');
  assert.equal(outcome, 'done'); assert.equal(w.attacked, undefined);
  assert.equal(d.querySelectorAll('.reader script,.reader img,.reader iframe,.reader [onerror]').length, 0);
});

test('Archive folders, linked breadcrumbs, literal names and paging', async t => {
  const entries = [{ path: 'Docs/readme.md', kind: 'file', size: 100 }, { path: 'Docs/nested/file.txt', kind: 'file', size: 20 }, { path: '../outside', kind: 'file', size: 0, unsafePath: true }, { path: '<script>.txt', kind: 'file', size: 1 }];
  for (let n = 0; n < 240; n++) entries.push({ path: `file-${n}.txt`, kind: 'file', size: n });
  const { d, outcome } = await view(t, 'archive', { format: 'ZIP', entries, warnings: [], truncated: false });
  assert.equal(outcome, 'done'); assert.equal(d.querySelectorAll('tbody tr').length, 200);
  d.querySelector('.paging').click(); assert.equal(d.querySelectorAll('tbody tr').length, 243);
  [...d.querySelectorAll('.entry-name')].find(b => b.textContent.includes('Docs')).click();
  assert.equal(d.querySelectorAll('tbody tr').length, 2);
  assert.equal(d.querySelector('.breadcrumbs').textContent, 'Archive > Docs');
  d.querySelector('.entry-name').click();
  assert.equal(d.querySelector('.breadcrumbs').textContent, 'Archive > Docs > nested');
  assert.equal(d.querySelector('.breadcrumbs [aria-current=location]').textContent, 'nested');
  assert.match(d.querySelector('tbody').textContent, /file.txt/);
  d.querySelectorAll('.breadcrumbs a')[1].click();
  assert.equal(d.querySelectorAll('tbody tr').length, 2);
  d.querySelector('.breadcrumbs a').click();
  d.querySelector('.paging').click();
  assert.equal(d.querySelectorAll('tbody tr').length, 243);
  assert.match(d.querySelector('tbody').textContent, /<script>\.txt/);
  assert.equal(d.querySelector('tbody script'), null);
});

test('Subtitle parser handles WebVTT voices, settings, comments and invalid timestamps', () => {
  assert.equal(timestamp('01:02:03,456'), 3723.456);
  assert.equal(timestamp('02:03.456'), 123.456);
  assert.equal(timestamp('01:62:03.000'), null);
  assert.equal(cueText('<v Mira>Hello &amp; &#x1F30A;</v>'), 'Mira: Hello & 🌊');
  const data = parseSubtitles('WEBVTT\n\nNOTE ignore\n\nSTYLE\n::cue { color:red; }\n\nid\n00:01.000 --> 00:02.500 align:start\n<v Mira>Hello</v>\n\nbad\n00:03.000 --> 00:01.000\nWrong');
  assert.equal(data.cues.length, 1); assert.equal(data.invalid, 1); assert.equal(data.duration, 2.5);
  assert.throws(() => parseSubtitles('not subtitles'), /No valid/);
  assert.equal(parseSubtitles('WEBVTT\n').cues.length, 0);
});

test('Subtitle paging preserves timestamps and dialogue while stripping scripts', async t => {
  const source = Array.from({ length: 220 }, (_, i) => `${i + 1}\n00:00:01,000 --> 00:00:02,000\n${i === 210 ? '<i>Unique &amp; special</i>' : 'Hello'}<script>window.attacked=1</script>`).join('\n\n');
  const { w, d, outcome } = await view(t, 'subtitles', source);
  assert.equal(outcome, 'done'); assert.equal(d.querySelectorAll('.cue').length, 200);
  d.querySelector('.paging').click(); assert.equal(d.querySelectorAll('.cue').length, 220);
  assert.equal(d.querySelectorAll('.cue-text')[210].textContent, 'Unique & special');
  assert.match(d.querySelectorAll('.cue-time')[210].textContent, /00:00:01.000.*00:00:02.000/);
  assert.equal(w.attacked, undefined);
  assert.equal(d.querySelectorAll('.cue script').length, 0);
});

test('EPUB contents, chapter navigation, cover and embedded images remain offline', async t => {
  const png = 'data:image/png;base64,aGVsbG8=';
  const book = { title: 'Book <title>', authors: ['A. Writer'], language: 'en', totalChapters: 3, truncated: true, cover: png,
    resources: { 'Book/image.png': png }, toc: [{ title: 'First', path: 'Book/text/a.xhtml' }, { title: 'Second', path: 'Book/text/b.xhtml' }, { title: 'Later', path: 'Book/text/c.xhtml' }],
    chapters: [{ title: 'First', path: 'Book/text/a.xhtml', html: '<h1>First section</h1><img src="../image.png"><a href="b.xhtml">Continue</a><script>window.attacked=1</script><img src="https://example.com/pixel" onerror="window.attacked=1"><iframe src="file:///etc/passwd"></iframe>' }, { title: 'Second', path: 'Book/text/b.xhtml', html: '<h1>Second section</h1><p>The end.</p>' }] };
  const { w, d, outcome } = await view(t, 'epub', book);
  assert.equal(outcome, 'done'); assert.equal(w.attacked, undefined);
  assert.equal(d.querySelector('.book-title').textContent, 'Book <title>');
  assert.equal(d.querySelectorAll('.reader img').length, 2);
  assert.equal(d.querySelectorAll('.reader script,.reader iframe,.reader [onerror]').length, 0);
  assert.equal(d.querySelectorAll('#sidebar button:disabled').length, 1);
  d.querySelector('.book-body a').click();
  assert.match(d.querySelector('.book-body').textContent, /Second section/);
  assert.match(d.querySelector('#status').textContent, /Excerpt from 3/);
  d.querySelector('#sidebar button').click(); assert.match(d.querySelector('.book-body').textContent, /First section/);
});
