// Notebook files may store multiline values as strings or arrays of lines.
export function text(value) {
  if (typeof value === 'string') return value;
  if (Array.isArray(value) && value.every(line => typeof line === 'string')) return value.join('');
  return '';
}

export const limits = { text: 100_000, image: 8 * 1024 * 1024, outputs: 50, page: 12 };

export function notebook(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Not a Jupyter notebook');
  let cells;
  if (value.nbformat === 4 && Array.isArray(value.cells)) {
    cells = value.cells;
  } else if (value.nbformat === 3 && Array.isArray(value.worksheets)) {
    if (!value.worksheets.every(sheet => sheet && Array.isArray(sheet.cells))) throw new Error('Invalid notebook worksheets');
    cells = value.worksheets.flatMap(sheet => sheet.cells).map(legacyCell);
  } else {
    throw new Error('Expected a Jupyter notebook in format 3 or 4');
  }
  if (!cells.every(cell => cell && typeof cell === 'object' && typeof cell.cell_type === 'string')) {
    throw new Error('Invalid notebook cell');
  }
  const language = value.metadata?.language_info?.name ?? value.metadata?.kernelspec?.language;
  return { cells, language: typeof language === 'string' ? language : '', version: value.nbformat };
}

function legacyCell(cell) {
  if (!cell || typeof cell !== 'object') return cell;
  const heading = cell.cell_type === 'heading';
  return {
    ...cell,
    cell_type: heading ? 'markdown' : cell.cell_type,
    source: heading ? '#'.repeat(Math.max(1, Math.min(6, Number(cell.level) || 1))) + ' ' + text(cell.source) : cell.input ?? cell.source,
    execution_count: cell.prompt_number,
    outputs: Array.isArray(cell.outputs) ? cell.outputs.map(output => {
      if (!output || typeof output !== 'object') return output;
      const data = {};
      for (const [old, mime] of Object.entries({ text: 'text/plain', html: 'text/html', png: 'image/png', jpeg: 'image/jpeg', svg: 'image/svg+xml', latex: 'text/latex', json: 'application/json' })) {
        if (Object.hasOwn(output, old)) data[mime] = output[old];
      }
      return { ...output, data, output_type: ({ pyout: 'execute_result', pyerr: 'error' })[output.output_type] ?? output.output_type,
        execution_count: output.prompt_number, name: output.stream };
    }) : []
  };
}

export function bundle(value) {
  const result = Object.create(null);
  if (!value || typeof value !== 'object' || Array.isArray(value)) return result;
  for (const [mime, data] of Object.entries(value)) {
    result[mime] = mime === 'application/json' || mime.endsWith('+json') ? data : text(data);
  }
  return result;
}

export function prompt(count) {
  return Number.isSafeInteger(count) && count >= 0 ? String(count) : ' ';
}
