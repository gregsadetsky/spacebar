(function () {
  "use strict";
  const sb = window.spacebar;
  const tree = document.getElementById("tree");
  const json = document.getElementById("json");
  const status = document.getElementById("status");
  const pageSize = 150;
  let serialized;

  function element(tag, className, text) {
    const node = document.createElement(tag);
    node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function countLabel(value) {
    const array = Array.isArray(value);
    const count = array ? value.length : Object.keys(value).length;
    return count.toLocaleString() + (array ? " item" : " key") + (count === 1 ? "" : "s");
  }

  function nodeFor(key, value, root) {
    const container = value !== null && typeof value === "object";
    const row = element(container ? "summary" : "div", "row");
    row.append(element("span", "key", key));
    if (!container) {
      const type = value === null ? "null" : typeof value;
      const text = JSON.stringify(value);
      row.append(element("span", "type", type));
      if (text.length > 300) {
        const details = element("details", "long-value");
        details.append(element("summary", "value " + type, text.slice(0, 240) + "…"));
        details.addEventListener("toggle", function () {
          if (details.open && details.childElementCount === 1) details.append(element("pre", "value " + type, text));
        });
        row.append(details);
      } else {
        row.append(element("span", "value " + type, text));
      }
      return row;
    }

    const array = Array.isArray(value);
    const keys = array ? null : Object.keys(value).sort();
    const count = array ? value.length : keys.length;
    row.append(element("span", "type", array ? "array" : "dictionary"));
    row.append(element("span", "count", countLabel(value)));
    const details = element("details", "branch");
    const children = element("div", "children");
    let rendered = 0;
    const more = element("button", "more");
    function nextPage() {
      more.remove();
      const end = Math.min(rendered + pageSize, count);
      const fragment = document.createDocumentFragment();
      for (; rendered < end; rendered++) {
        const childKey = array ? rendered : keys[rendered];
        fragment.append(nodeFor(array ? "[" + childKey + "]" : childKey, value[childKey], false));
      }
      children.append(fragment);
      if (rendered < count) {
        more.textContent = "Show next " + Math.min(pageSize, count - rendered) + " · " + (count - rendered).toLocaleString() + " remaining";
        children.append(more);
      }
    }
    more.addEventListener("click", nextPage);
    details.append(row, children);
    details.addEventListener("toggle", function () {
      if (details.open && rendered === 0) nextPage();
    });
    if (root) { nextPage(); details.open = true; }
    return details;
  }

  function jsonText() {
    if (serialized === undefined) serialized = JSON.stringify(sb.data, null, 2);
    return serialized;
  }

  function showJSON(show) {
    tree.hidden = show;
    json.hidden = !show;
    if (show) json.value = jsonText();
    document.getElementById("tree-button").setAttribute("aria-pressed", String(!show));
    document.getElementById("json-button").setAttribute("aria-pressed", String(show));
  }

  function copyFallback() {
    const wasJSON = !json.hidden;
    showJSON(true);
    json.focus();
    json.select();
    let copied = false;
    try { copied = document.execCommand("copy"); } catch (_) { /* offer manual copy below */ }
    if (copied) {
      showJSON(wasJSON);
      document.getElementById("copy").focus();
      status.textContent = "Copied JSON";
    } else {
      status.textContent = "JSON selected — press ⌘C to copy";
    }
  }

  try {
    document.documentElement.dataset.theme = sb.theme;
    document.getElementById("title").textContent = sb.file.name;
    const size = sb.file.size < 1024 ? sb.file.size + " bytes" : (sb.file.size / 1024).toLocaleString(undefined, { maximumFractionDigits: 1 }) + " KB";
    document.getElementById("meta").textContent = size;
    tree.append(nodeFor("root", sb.data, true));
    document.getElementById("tree-button").addEventListener("click", function () { showJSON(false); });
    document.getElementById("json-button").addEventListener("click", function () { showJSON(true); });
    document.getElementById("copy").addEventListener("click", function () {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(jsonText()).then(function () { status.textContent = "Copied JSON"; }, copyFallback);
      } else { copyFallback(); }
    });
    sb.done();
  } catch (error) {
    sb.fail("Could not display property list: " + error.message);
  }
})();
