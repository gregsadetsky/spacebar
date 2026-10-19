// sqlite plugin for spacebar. the host already opened the file read-only and
// handed us a summary (tables, columns, counts, first 50 rows, views,
// indexes). we only render. see PLUGINS.md for the payload shape.
(function () {
  "use strict";
  var sb = window.spacebar;
  var d = sb.data;
  var state = { selected: 0, tab: "rows", sort: {} }; // sort[tableName] = {col, dir: "asc"|"desc"}
  var items = []; // nav items: {kind: table|view|index, obj}

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" }[c]; });
  }
  function fmt(n) { return Number(n).toLocaleString("en-US"); }
  function bytes(n) {
    if (n < 1024) return n + " B";
    if (n < 1048576) return (n / 1024).toFixed(1) + " KB";
    if (n < 1073741824) return (n / 1048576).toFixed(1) + " MB";
    return (n / 1073741824).toFixed(2) + " GB";
  }

  function renderNav() {
    var html = "";
    function section(title, list, kind, count) {
      html += "<h3>" + title + "</h3>";
      if (!list.length) { html += "<div class=\"empty\">none</div>"; return; }
      list.forEach(function (o) {
        var idx = items.length;
        items.push({ kind: kind, obj: o });
        html += "<div class=\"item" + (idx === state.selected ? " selected" : "") + "\" data-i=\"" + idx + "\">" +
          "<span class=\"n\" title=\"" + esc(o.name) + "\">" + esc(o.name) + "</span>" +
          "<span class=\"c\">" + (count ? count(o) : "") + "</span></div>";
      });
    }
    items = [];
    section("Tables", d.tables, "table", function (t) { return t.rowCount === null ? "?" : fmt(t.rowCount); });
    section("Views", d.views, "view");
    section("Indexes", d.indexes, "index", function (i) { return esc(i.table); });
    document.getElementById("nav").innerHTML = html;
  }

  function cell(v) {
    if (v === null || v === undefined) return "<td class=\"null\">NULL</td>";
    if (typeof v === "number") return "<td class=\"num\">" + esc(v) + "</td>";
    if (typeof v === "object" && "blob" in v) return "<td class=\"blob\">blob · " + bytes(v.blob) + "</td>";
    var s = String(v);
    if (s.length > 200) s = s.slice(0, 197) + "…";
    return "<td title=\"" + esc(String(v).slice(0, 1000)) + "\">" + esc(s) + "</td>";
  }

  function renderDetail() {
    var el = document.getElementById("detail");
    var item = items[state.selected];
    if (!item) { el.innerHTML = "<div class=\"caption\">Empty database</div>"; return; }
    var o = item.obj;
    var html = "";
    if (item.kind === "table") {
      html += "<div class=\"tabs\">" +
        "<button data-tab=\"rows\"" + (state.tab === "rows" ? " class=\"active\"" : "") + ">Rows</button>" +
        "<button data-tab=\"schema\"" + (state.tab === "schema" ? " class=\"active\"" : "") + ">Schema</button></div>";
      if (state.tab === "schema") {
        html += "<div class=\"scroll\"><pre>" + esc(o.sql || "") + "</pre></div>";
      } else {
        var sort = state.sort[o.name] || null;
        var rows = o.sample.slice();
        if (sort) {
          var ci = sort.col, dir = sort.dir === "asc" ? 1 : -1;
          rows.sort(function (a, b) {
            var x = a[ci], y = b[ci];
            var xn = x === null || x === undefined, yn = y === null || y === undefined;
            if (xn && yn) return 0; if (xn) return 1; if (yn) return -1;   // nulls last either way
            if (typeof x === "number" && typeof y === "number") return (x - y) * dir;
            if (typeof x === "object" || typeof y === "object") return 0;  // blobs keep their place
            return String(x).localeCompare(String(y), undefined, { numeric: true }) * dir;
          });
        }
        html += "<div class=\"scroll\"><table><thead><tr>" + o.columns.map(function (c, i) {
          var active = sort && sort.col === i;
          return "<th class=\"sortable" + (active ? " sorted" : "") + "\" data-col=\"" + i + "\" title=\"click to sort\">" + esc(c.name) +
            (active ? "<span class=\"arrow\">" + (sort.dir === "asc" ? "▲" : "▼") + "</span>" : "") + "</th>";
        }).join("") + "</tr></thead><tbody>";
        rows.forEach(function (row) { html += "<tr>" + row.map(cell).join("") + "</tr>"; });
        html += "</tbody></table>";
        var shown = o.sample.length;
        var total = o.rowCount === null ? "an unknown number of" : fmt(o.rowCount);
        html += "<div class=\"caption\">" + (shown ? "first " + shown + " of " + total + " rows" : "no rows") +
          (sort ? ", sorted within these " + shown : "") +
          (o.rowCount === null ? " (count skipped, table too large for the 200 ms budget)" : "") + "</div></div>";
      }
    } else {
      html += "<div class=\"tabs\"><button class=\"active\">" + (item.kind === "view" ? "View" : "Index on " + esc(o.table)) + "</button></div>";
      html += "<div class=\"scroll\"><pre>" + esc(o.sql || "(no sql, auto index)") + "</pre></div>";
    }
    el.innerHTML = html;
  }

  function select(i) {
    if (i < 0 || i >= items.length) return;
    state.selected = i;
    renderNav();
    renderDetail();
    var node = document.querySelector("nav .item.selected");
    if (node && node.scrollIntoView) node.scrollIntoView({ block: "nearest" });
  }

  document.addEventListener("click", function (e) {
    var item = e.target.closest ? e.target.closest("[data-i]") : null;
    if (item) return select(parseInt(item.getAttribute("data-i"), 10));
    var tab = e.target.closest ? e.target.closest("[data-tab]") : null;
    if (tab) { state.tab = tab.getAttribute("data-tab"); renderDetail(); return; }
    var th = e.target.closest ? e.target.closest("th[data-col]") : null;
    if (th && items[state.selected] && items[state.selected].kind === "table") {
      var name = items[state.selected].obj.name, col = parseInt(th.getAttribute("data-col"), 10);
      var cur = state.sort[name];
      if (!cur || cur.col !== col) state.sort[name] = { col: col, dir: "asc" };     // none -> asc
      else if (cur.dir === "asc") state.sort[name] = { col: col, dir: "desc" };     // asc -> desc
      else delete state.sort[name];                                                  // desc -> none
      renderDetail();
    }
  });
  document.addEventListener("keydown", function (e) {
    if (e.key === "ArrowDown") { select(state.selected + 1); e.preventDefault(); }
    else if (e.key === "ArrowUp") { select(state.selected - 1); e.preventDefault(); }
    else if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
      if (items[state.selected] && items[state.selected].kind === "table") { state.tab = state.tab === "rows" ? "schema" : "rows"; renderDetail(); }
    }
  });

  try {
    if (!d || !Array.isArray(d.tables)) throw new Error("payload has no tables array");
    renderNav();
    renderDetail();
    sb.done();
  } catch (e) {
    sb.fail("SQLite plugin crashed: " + (e && e.message ? e.message : e));
  }
})();
