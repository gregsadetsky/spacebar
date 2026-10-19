import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { JSDOM } from 'jsdom';
import { notebook, text, bundle, limits } from '../model.mjs';

const html = await readFile(new URL('../../../plugins/notebook/index.html', import.meta.url), 'utf8');
const js = await readFile(new URL('../../../plugins/notebook/vendor/notebook.js', import.meta.url), 'utf8');
const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN3sAAAAASUVORK5CYII=';
const nb = cells => ({ nbformat: 4, nbformat_minor: 5, metadata: { language_info: { name: 'python' } }, cells });
const code = outputs => ({ cell_type: 'code', source: 'print("hello")', execution_count: 1, outputs });
const display = data => ({ output_type: 'display_data', data });

async function view(t, data, theme = 'light') {
  const dom = new JSDOM(html, { runScripts: 'outside-only', pretendToBeVisual: true, url: 'https://spacebar.invalid/' });
  t.after(() => dom.window.close());
  const w = dom.window;
  // Fail if rendering itself attempts network access, independent of the host's block.
  w.fetch = () => { throw new Error('Unexpected fetch'); };
  w.XMLHttpRequest = class { constructor() { throw new Error('Unexpected XHR'); } };
  w.WebSocket = class { constructor() { throw new Error('Unexpected WebSocket'); } };
  const outcome = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Viewer timed out')), 3000);
    const finish = message => { clearTimeout(timer); resolve(message); };
    w.spacebar = { data, file: { name: '<example>.ipynb' }, theme, done: () => finish('done'), fail: finish };
    try { w.eval(js); } catch (error) { clearTimeout(timer); reject(error); }
  });
  return { w, d: w.document, outcome };
}

async function waitUntil(predicate) {
  const end = Date.now() + 2000;
  while (!predicate()) {
    if (Date.now() > end) throw new Error('Interaction timed out');
    await new Promise(resolve => setTimeout(resolve, 10));
  }
}

test('multiline fields, MIME data and legacy worksheets retain their values', () => {
  assert.equal(text(['a\n', 'b']), 'a\nb');
  assert.equal(text(['a', 3]), '');
  assert.equal(bundle({ 'text/plain': ['a', 'b'] })['text/plain'], 'ab');
  assert.equal(Object.getPrototypeOf(bundle({})), null);
  const data = notebook({ nbformat: 3, worksheets: [{ cells: [
    { cell_type: 'heading', level: 2, source: ['Legacy'] },
    { cell_type: 'code', input: ['1 + 1'], prompt_number: 2, outputs: [{ output_type: 'pyout', text: ['2'], prompt_number: 2 }] }
  ] }] });
  assert.equal(data.cells[0].source, '## Legacy');
  assert.equal(data.cells[1].outputs[0].data['text/plain'][0], '2');
  assert.equal(data.cells[1].outputs[0].output_type, 'execute_result');
});

test('renders Markdown, highlighted code, math, tables, images, ANSI and errors', async t => {
  const { d, outcome } = await view(t, nb([
    { cell_type: 'markdown', source: ['# Analysis\n\n', '**Result**: $E=mc^2$\n\n![attached](attachment:plot.png)'], attachments: { 'plot.png': { 'image/png': png } } },
    code([
      { output_type: 'stream', text: ['\u001b[31mhello\u001b[0m\n'] },
      { output_type: 'execute_result', execution_count: 1, data: { 'text/plain': 'fallback', 'text/html': '<table><tr><th>City</th></tr><tr><td>Oslo</td></tr></table>' } },
      display({ 'image/png': png }),
      display({ 'image/svg+xml': '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><circle cx="5" cy="5" r="4" style="fill: none; stroke: #123456; stroke-width: 2; clip-path: url(#clip)"/></svg>' }),
      { output_type: 'error', ename: 'ValueError', evalue: 'bad', traceback: ['ValueError: bad'] },
      display({ 'text/latex': '$$x^2$$' }),
      display({ 'application/json': { ok: true } })
    ])
  ]), 'dark');
  assert.equal(outcome, 'done');
  assert.equal(d.documentElement.dataset.theme, 'dark');
  assert.equal(d.querySelector('#title').textContent, '<example>.ipynb');
  assert.equal(d.querySelector('.markdown h1').firstChild.textContent, 'Analysis');
  assert.equal(d.querySelectorAll('.katex').length, 2);
  assert.ok(d.querySelector('.source .hljs-built_in'));
  assert.equal(d.querySelector('td').textContent, 'Oslo');
  assert.equal(d.querySelectorAll('#notebook img').length, 3);
  const svg = decodeURIComponent(d.querySelector('img[src^="data:image/svg"]').src.split(',').slice(1).join(','));
  assert.match(svg, /width="10"/);
  assert.match(svg, /cx="5"/);
  assert.match(svg, /r="4"/);
  assert.match(svg, /fill="none"/);
  assert.match(svg, /stroke="(?:#123456|rgb\(18, 52, 86\))"/);
  assert.match(svg, /stroke-width="2"/);
  assert.match(svg, /clip-path="url\((?:&quot;)?#clip(?:&quot;)?\)"/);
  assert.doesNotMatch(svg, /style=/);
  assert.ok(d.querySelector('.ansi-red-fg'));
  assert.match(d.querySelector('.error').textContent, /ValueError/);
  assert.match(d.querySelector('#notebook').textContent, /"ok": true/);
  assert.ok(!d.querySelector('#notebook').textContent.includes('fallback'));
});

test('strips active HTML, external resources and unsafe links; JavaScript MIME never runs', async t => {
  const attack = '<script>window.pwned=1</script><iframe src="https://example.com"></iframe>' +
    '<style>@import "https://example.com/style";</style><img src="https://example.com/pixel" onerror="window.pwned=1">' +
    '<a href="javascript:window.pwned=1">click</a><a href="file:///etc/passwd">file</a>' +
    '<a href="https://example.com">web</a><form action="https://example.com"><input></form>' +
    '<p style="background:url(https://example.com/pixel)">safe text</p>';
  const { w, d, outcome } = await view(t, nb([
    { cell_type: 'markdown', source: attack },
    code([display({ 'text/html': attack }), display({ 'application/javascript': 'window.pwned=1' }),
      display({ 'image/svg+xml': '<svg xmlns="http://www.w3.org/2000/svg" onload="window.pwned=1"><script>window.pwned=1</script><foreignObject><p>bad</p></foreignObject><style>@import "https://example.com";</style><image href="https://example.com"/><use href="https://example.com/a.svg#x"/><circle r="5" fill="url(https://example.com/a.svg#x)"/></svg>' })])
  ]));
  assert.equal(outcome, 'done');
  assert.equal(w.pwned, undefined);
  assert.equal(d.querySelectorAll('#notebook script, #notebook iframe, #notebook style, #notebook form, #notebook input, #notebook [onerror], #notebook [onload], #notebook [style]').length, 0);
  assert.equal(d.querySelectorAll('#notebook a[href]').length, 0);
  assert.equal(d.querySelectorAll('#notebook img').length, 1);
  const svg = decodeURIComponent(d.querySelector('#notebook img').src.split(',').slice(1).join(','));
  assert.doesNotMatch(svg, /script|foreignObject|onload|https:\/\/example/);
  assert.match(d.querySelector('#notebook').textContent, /no static preview/);
});

test('pages large notebooks, hides code, collapses long source and caps outputs', async t => {
  const cells = Array.from({ length: 26 }, (_, n) => ({ ...code([]), source: `print(${n})` }));
  cells[0].source = Array.from({ length: 30 }, () => 'x = 1').join('\n');
  cells[0].outputs = Array.from({ length: limits.outputs + 1 }, () => ({ output_type: 'stream', text: 'ok' }));
  const { d, outcome } = await view(t, nb(cells));
  assert.equal(outcome, 'done');
  assert.ok(d.querySelectorAll('.cell').length <= 12);
  assert.ok(d.querySelector('.source details:not([open])'));
  assert.equal(d.querySelectorAll('.output-row').length, limits.outputs);
  assert.match(d.querySelector('#notebook').textContent, /first 50 of 51/);
  d.querySelector('#toggle-code').click();
  assert.ok(d.querySelector('#notebook.hide-code'));
  assert.equal(d.querySelector('#toggle-code').getAttribute('aria-pressed'), 'true');
  while (!d.querySelector('#more').hidden) {
    d.querySelector('#more').click();
    await waitUntil(() => !d.querySelector('#more').disabled);
  }
  assert.equal(d.querySelectorAll('.cell').length, 26);
  assert.equal(d.querySelector('#progress').textContent, '26 of 26 cells');
});

test('truncates text, falls back from oversized HTML, and explains unsupported outputs', async t => {
  const { d, outcome } = await view(t, nb([code([
    { output_type: 'stream', text: 'a'.repeat(limits.text + 1) },
    display({ 'text/html': 'b'.repeat(limits.text + 1), 'text/plain': 'small fallback' }),
    display({ 'application/vnd.jupyter.widget-view+json': { model_id: 'widget' } }),
    display({ 'text/html': '<script>window.pwned=1</script>', 'text/plain': 'script output fallback' }),
    display({ 'image/png': 'invalid!' })
  ])]));
  assert.equal(outcome, 'done');
  assert.equal(d.querySelector('.output pre').textContent.length, limits.text);
  assert.match(d.querySelector('#notebook').textContent, /small fallback/);
  assert.match(d.querySelector('#notebook').textContent, /no static preview/);
  assert.match(d.querySelector('#notebook').textContent, /script output fallback/);
  assert.match(d.querySelector('#notebook').textContent, /Invalid saved image/);
});

test('empty, malformed and legacy notebooks have useful results', async t => {
  const empty = await view(t, nb([]));
  assert.equal(empty.outcome, 'done');
  assert.match(empty.d.querySelector('#notebook').textContent, /no cells/);
  assert.match((await view(t, { nbformat: 4, cells: [null] })).outcome, /Invalid notebook cell/);
  assert.match((await view(t, {})).outcome, /Expected a Jupyter notebook/);
  const legacy = await view(t, { nbformat: 3, worksheets: [{ cells: [
    { cell_type: 'heading', level: 2, source: 'Old notebook' },
    { cell_type: 'code', input: '2', outputs: [{ output_type: 'pyout', text: '2', prompt_number: 1 }] }
  ] }] });
  assert.equal(legacy.outcome, 'done');
  assert.match(legacy.d.querySelector('h2').textContent, /Old notebook/);
  assert.equal(legacy.d.querySelector('.output pre').textContent, '2');
});
