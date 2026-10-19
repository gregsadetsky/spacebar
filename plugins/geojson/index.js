// geojson plugin for spacebar. zero dependencies: parses, summarizes, draws
// an svg map on top of the inline world outline (world.js), lists properties.
(function () {
  "use strict";
  var sb = window.spacebar;
  var MAX_VERTICES = 20000;
  var MAX_ROWS = 100;
  var MAX_COLUMNS = 40;
  var GEOMETRY_TYPES = ["Point", "MultiPoint", "LineString", "MultiLineString", "Polygon", "MultiPolygon", "GeometryCollection"];

  function fail(message) { sb.fail(message); }

  function parse(text) {
    var root;
    try { root = JSON.parse(text); } catch (e) { return fail("Not valid JSON: " + e.message); }
    if (!root || typeof root !== "object" || typeof root.type !== "string") return fail("Not valid GeoJSON: no \"type\"");
    if (root.type === "FeatureCollection") return { root: root, features: Array.isArray(root.features) ? root.features : [] };
    if (root.type === "Feature") return { root: root, features: [root] };
    if (GEOMETRY_TYPES.indexOf(root.type) >= 0) return { root: root, features: [{ type: "Feature", geometry: root, properties: {} }] };
    return fail("Not valid GeoJSON: unknown type \"" + root.type + "\"");
  }

  // calls cb(coords, kind) for every point list in a geometry.
  // kind: "point" (single position), "line" (open), "ring" (closed)
  function eachPart(geom, cb) {
    if (!geom || typeof geom !== "object") return;
    var c = geom.coordinates;
    switch (geom.type) {
      case "Point": if (isPos(c)) cb([c], "point"); break;
      case "MultiPoint": (c || []).forEach(function (p) { if (isPos(p)) cb([p], "point"); }); break;
      case "LineString": cb(c || [], "line"); break;
      case "MultiLineString": (c || []).forEach(function (l) { cb(l || [], "line"); }); break;
      case "Polygon": (c || []).forEach(function (r) { cb(r || [], "ring"); }); break;
      case "MultiPolygon": (c || []).forEach(function (poly) { (poly || []).forEach(function (r) { cb(r || [], "ring"); }); }); break;
      case "GeometryCollection": (geom.geometries || []).forEach(function (g) { eachPart(g, cb); }); break;
    }
  }
  function isPos(p) { return Array.isArray(p) && p.length >= 2 && isFinite(p[0]) && isFinite(p[1]); }

  function summarize(features) {
    var types = {}, vertices = 0;
    var bbox = [Infinity, Infinity, -Infinity, -Infinity];
    features.forEach(function (f) {
      var g = f && f.geometry;
      var t = g && g.type ? g.type : "null";
      types[t] = (types[t] || 0) + 1;
      eachPart(g, function (coords) {
        coords.forEach(function (p) {
          if (!isPos(p)) return;
          vertices++;
          if (p[0] < bbox[0]) bbox[0] = p[0];
          if (p[1] < bbox[1]) bbox[1] = p[1];
          if (p[0] > bbox[2]) bbox[2] = p[0];
          if (p[1] > bbox[3]) bbox[3] = p[1];
        });
      });
    });
    return { types: types, vertices: vertices, bbox: vertices ? bbox : null };
  }

  function fmt(n) { return n.toLocaleString("en-US"); }
  function round(n) { return Math.round(n * 1000) / 1000; }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;" }[c]; });
  }

  // equirectangular with the x axis scaled by cos(mid latitude)
  function makeProjection(bbox) {
    var b = bbox ? bbox.slice() : [-180, -90, 180, 90];
    if (b[2] - b[0] < 1e-9) { b[0] -= 1; b[2] += 1; }
    if (b[3] - b[1] < 1e-9) { b[1] -= 1; b[3] += 1; }
    var midLat = (b[1] + b[3]) / 2;
    var kx = Math.max(0.2, Math.cos(midLat * Math.PI / 180));
    function project(p) { return [p[0] * kx, -p[1]]; }
    var min = project([b[0], b[3]]), max = project([b[2], b[1]]);
    var w = max[0] - min[0], h = max[1] - min[1];
    var pad = Math.max(w, h) * 0.05;
    return { project: project, viewBox: [min[0] - pad, min[1] - pad, w + 2 * pad, h + 2 * pad], span: Math.max(w, h) };
  }

  function svgEl(name, attrs) {
    var el = document.createElementNS("http://www.w3.org/2000/svg", name);
    for (var k in attrs) el.setAttribute(k, attrs[k]);
    return el;
  }

  function pathData(coords, proj, step, close) {
    var d = [], n = coords.length;
    for (var i = 0; i < n; i++) {
      if (step > 1 && i % step !== 0 && i !== n - 1) continue;
      var p = coords[i];
      if (!isPos(p)) continue;
      var q = proj.project(p);
      d.push((d.length ? "L" : "M") + round(q[0]) + " " + round(q[1]));
    }
    if (close && d.length) d.push("Z");
    return d.join("");
  }

  function renderMap(features, summary, proj, step) {
    var map = document.getElementById("map");
    var svg = svgEl("svg", { viewBox: proj.viewBox.join(" "), preserveAspectRatio: "xMidYMid meet" });

    var world = svgEl("g", { "class": "world" });
    var worldPath = [];
    (window.WORLD_RINGS || []).forEach(function (flat) {
      var ring = [];
      for (var i = 0; i < flat.length; i += 2) ring.push([flat[i], flat[i + 1]]);
      worldPath.push(pathData(ring, proj, 1, true));
    });
    world.appendChild(svgEl("path", { d: worldPath.join(""), "fill-rule": "nonzero" }));
    svg.appendChild(world);

    var layer = svgEl("g");
    var pointCount = (summary.types.Point || 0) + (summary.types.MultiPoint || 0);
    var pointRadius = proj.span * (pointCount > 5000 ? 0.0015 : pointCount > 500 ? 0.003 : 0.006);
    var pointCounter = 0;
    features.forEach(function (f, idx) {
      var g = svgEl("g", { "class": "feature", "data-i": idx });
      var polygon = [], lines = [], points = [];
      eachPart(f && f.geometry, function (coords, kind) {
        if (kind === "point") {
          pointCounter++;
          if (step > 1 && pointCounter % step !== 0) return;
          points.push(coords[0]);
        } else if (kind === "ring") polygon.push(pathData(coords, proj, step, true));
        else lines.push(pathData(coords, proj, step, false));
      });
      if (polygon.length) g.appendChild(svgEl("path", { "class": "polygon", d: polygon.join("") }));
      if (lines.length) g.appendChild(svgEl("path", { "class": "line", d: lines.join("") }));
      points.forEach(function (p) {
        var q = proj.project(p);
        g.appendChild(svgEl("circle", { cx: round(q[0]), cy: round(q[1]), r: round(pointRadius) }));
      });
      if (g.childNodes.length) layer.appendChild(g);
    });
    svg.appendChild(layer);
    map.appendChild(svg);
    if (!summary.vertices) {
      var empty = document.createElement("div");
      empty.className = "empty";
      empty.textContent = "No geometry to draw";
      map.appendChild(empty);
    }
    return layer;
  }

  function cell(v) {
    if (v === null || v === undefined) return "";
    if (typeof v === "object") { try { v = JSON.stringify(v); } catch (e) { v = String(v); } }
    v = String(v);
    return v.length > 120 ? v.slice(0, 117) + "…" : v;
  }

  function renderTable(features) {
    var rows = features.slice(0, MAX_ROWS);
    var columns = [];
    rows.forEach(function (f) {
      var props = f && f.properties;
      if (!props || typeof props !== "object") return;
      Object.keys(props).forEach(function (k) { if (columns.indexOf(k) < 0 && columns.length < MAX_COLUMNS) columns.push(k); });
    });
    var html = "<table><thead><tr><th>#</th><th>geometry</th>" + columns.map(function (c) { return "<th>" + escapeHtml(c) + "</th>"; }).join("") + "</tr></thead><tbody>";
    rows.forEach(function (f, i) {
      var props = (f && f.properties) || {};
      var t = f && f.geometry && f.geometry.type ? f.geometry.type : "null";
      html += "<tr data-i=\"" + i + "\"><td class=\"num\">" + i + "</td><td>" + escapeHtml(t) + "</td>";
      columns.forEach(function (c) {
        var v = props[c];
        html += "<td" + (typeof v === "number" ? " class=\"num\"" : "") + ">" + escapeHtml(cell(v)) + "</td>";
      });
      html += "</tr>";
    });
    html += "</tbody></table>";
    if (features.length > MAX_ROWS) html += "<div class=\"caption\">first " + MAX_ROWS + " of " + fmt(features.length) + " features</div>";
    if (!columns.length && rows.length) html += "<div class=\"caption\">no properties</div>";
    document.getElementById("table").innerHTML = html;
  }

  function renderPanel(f, idx) {
    var panel = document.getElementById("panel");
    if (!f) { panel.innerHTML = "<div class=\"hint\">Hover a feature for its properties.</div>"; return; }
    var props = (f && f.properties) || {};
    var keys = Object.keys(props);
    var t = f.geometry && f.geometry.type ? f.geometry.type : "null";
    var html = "<h3>#" + idx + " · " + escapeHtml(t) + (f.id !== undefined ? " · id " + escapeHtml(cell(f.id)) : "") + "</h3>";
    if (!keys.length) html += "<div class=\"hint\">no properties</div>";
    else {
      html += "<dl>";
      keys.forEach(function (k) { html += "<dt title=\"" + escapeHtml(k) + "\">" + escapeHtml(k) + "</dt><dd>" + escapeHtml(cell(props[k])) + "</dd>"; });
      html += "</dl>";
    }
    panel.innerHTML = html;
  }

  function wireInteraction(features, layer) {
    var hovered = null;
    function setClass(idx, on) {
      var g = layer.querySelector("g[data-i=\"" + idx + "\"]");
      if (g) g.classList.toggle("hover", on);
      var tr = document.querySelector("tr[data-i=\"" + idx + "\"]");
      if (tr) tr.classList.toggle("hover", on);
    }
    function hover(idx) {
      if (hovered !== null) setClass(hovered, false);
      hovered = idx;
      if (idx !== null) { setClass(idx, true); renderPanel(features[idx], idx); }
      else renderPanel(null);
    }
    function indexOf(el) {
      var node = el.closest ? el.closest("[data-i]") : null;
      return node ? parseInt(node.getAttribute("data-i"), 10) : null;
    }
    document.addEventListener("mouseover", function (e) { var i = indexOf(e.target); if (i !== null) hover(i); });
    document.addEventListener("mouseout", function (e) { var i = indexOf(e.target); if (i !== null && i === hovered) hover(null); });
  }

  try {
    var parsed = parse(sb.data);
    if (!parsed) return;
    var features = parsed.features;
    var summary = summarize(features);
    var step = summary.vertices > MAX_VERTICES ? Math.ceil(summary.vertices / MAX_VERTICES) : 1;
    var proj = makeProjection(summary.bbox);
    var layer = renderMap(features, summary, proj, step);
    renderTable(features);
    wireInteraction(features, layer);
    sb.done();
  } catch (e) {
    fail("GeoJSON plugin crashed: " + (e && e.message ? e.message : e));
  }
})();
