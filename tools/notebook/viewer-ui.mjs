export const sb = window.spacebar;
export const content = document.getElementById('content');
export const actions = document.getElementById('actions');
export const status = document.getElementById('status');
export function el(tag, className = '', text) {
  const node = document.createElement(tag); node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}
export function setup(meta) {
  document.documentElement.dataset.theme = sb.theme;
  document.getElementById('title').textContent = sb.file.name;
  document.getElementById('meta').textContent = meta;
}
export function button(label, action) { const node = el('button', '', label); node.type = 'button'; node.addEventListener('click', action); return node; }
export function search(label, onInput) { const node = el('input'); node.type = 'search'; node.placeholder = label; node.setAttribute('aria-label', label); node.addEventListener('input', () => onInput(node.value)); return node; }
export function size(bytes) { const n = Number(bytes); if (!Number.isFinite(n)) return '—'; if (n < 1024) return `${n} B`; const power = Math.min(4, Math.floor(Math.log(n) / Math.log(1024))); return `${(n / 1024 ** power).toLocaleString(undefined, { maximumFractionDigits: 1 })} ${['B','KB','MB','GB','TB'][power]}`; }
