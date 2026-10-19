import { notebook, text, limits, prompt } from './model.mjs';
import { element, notice, code, markdown, output } from './render.mjs';

const sb = window.spacebar;
const content = document.getElementById('notebook');
const more = document.getElementById('more');
const progress = document.getElementById('progress');

async function cellView(cell, index, language) {
  const section = element('section', `cell ${cell.cell_type === 'code' ? 'code-cell' : 'text-cell'}`);
  section.setAttribute('aria-label', `Cell ${index + 1}`);
  const source = text(cell.source);
  if (cell.cell_type === 'markdown') {
    const body = element('div', 'markdown');
    section.append(body);
    await markdown(body, source, cell.attachments ?? {});
  } else if (cell.cell_type === 'code') {
    const input = element('div', 'input');
    input.append(element('span', 'prompt', `In [${prompt(cell.execution_count)}]:`));
    const body = element('div', 'source');
    input.append(body);
    const collapsed = source.split('\n').length > 24;
    if (collapsed) {
      const details = element('details');
      details.append(element('summary', '', `Code · ${source.split('\n').length} lines`));
      code(details, source, language);
      body.append(details);
    } else { code(body, source, language); }
    section.append(input);
    const outputs = Array.isArray(cell.outputs) ? cell.outputs : [];
    for (const saved of outputs.slice(0, limits.outputs)) {
      const row = element('div', 'output-row');
      row.append(element('span', 'prompt', saved?.output_type === 'execute_result' ? `Out [${prompt(saved.execution_count)}]:` : ''));
      const rendered = element('div', 'output');
      row.append(rendered); section.append(row);
      try { await output(rendered, saved); }
      catch (_) { notice(rendered, 'This saved output could not be displayed.'); }
    }
    if (outputs.length > limits.outputs) notice(section, `Showing the first ${limits.outputs} of ${outputs.length} outputs.`);
  } else {
    const raw = element('div', 'raw');
    notice(raw, cell.cell_type === 'raw' ? 'Raw cell' : `Cell type: ${cell.cell_type}`);
    code(raw, source, ''); section.append(raw);
  }
  return section;
}

async function start() {
  const data = notebook(sb.data);
  let shown = 0;
  document.documentElement.dataset.theme = sb.theme;
  document.getElementById('title').textContent = sb.file.name;
  document.getElementById('meta').textContent = [data.language, `${data.cells.length.toLocaleString()} cells`, 'saved outputs'].filter(Boolean).join(' · ');
  async function next() {
    more.disabled = true;
    const started = performance.now();
    const end = Math.min(shown + limits.page, data.cells.length);
    while (shown < end) {
      try { content.append(await cellView(data.cells[shown], shown, data.language.toLowerCase())); }
      catch (_) { notice(content, `Cell ${shown + 1} could not be displayed.`); }
      shown++;
      // Stop a page early when saved outputs are expensive to render.
      if (performance.now() - started > 750) break;
      // Yield between cells to keep scrolling responsive during paging.
      await new Promise(resolve => setTimeout(resolve, 0));
    }
    more.hidden = shown === data.cells.length;
    more.textContent = `Show next ${Math.min(limits.page, data.cells.length - shown)} cells`;
    more.disabled = false;
    progress.textContent = `${shown.toLocaleString()} of ${data.cells.length.toLocaleString()} cells`;
  }
  more.addEventListener('click', () => next().catch(error => { progress.textContent = error.message; more.disabled = false; }));
  document.getElementById('toggle-code').addEventListener('click', event => {
    const hidden = content.classList.toggle('hide-code');
    event.currentTarget.textContent = hidden ? 'Show code' : 'Hide code';
    event.currentTarget.setAttribute('aria-pressed', String(hidden));
  });
  if (!data.cells.length) notice(content, 'This notebook has no cells.');
  await next();
  sb.done();
}

start().catch(error => sb.fail(error.message));
