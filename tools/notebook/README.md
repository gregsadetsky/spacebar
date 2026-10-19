# Offline document renderers

This build produces the notebook, Markdown, archive, EPUB and subtitle plugins.
Source lives here; generated bundles live in each plugin's `vendor` directory.
Normal app builds use the checked-in bundles and need no Node or downloads.

To change a renderer (Node 22):

```sh
npm ci --prefix tools/notebook --ignore-scripts
npm run build --prefix tools/notebook
npm test --prefix tools/notebook
make samples
make install
```

Commit source, lockfile changes and regenerated plugin files together. CI
rebuilds every bundle, checks the committed output and runs 12 tests against
the actual bundles in jsdom. `make test` covers the native host and manifests;
`make smoke` previews fixtures through the real Quick Look extension.

Shared UI and styles are in `viewer-ui.mjs` and `viewer.css`. Each plugin is
self-contained after building; installing it never needs another plugin.

## Markdown, archives, EPUB and subtitles

- `markdown-main.mjs` reuses the notebook's JupyterLab/Marked rendering,
  highlighting, KaTeX and sanitization. It adds source view, heading navigation
  and collapsible YAML/TOML front matter. Files are capped at 10 MiB and the
  rendered preview at 100,000 characters. Local and remote image files are
  unavailable; embedded supported images remain offline.
- `archive-main.mjs` consumes the native `archive` payload and provides
  folders, breadcrumbs, path search, name/size ordering and 200-row paging.
  ZIP, TAR, compressed TAR, 7z and RAR use the system libarchive. This viewer
  lists entries; it never extracts files. Header provenance is documented in
  `Packages/SpacebarKit/Sources/CArchive/README.md` at the repository root.
- `epub-main.mjs` consumes native EPUB 2/3 metadata and a bounded excerpt.
  It shows the cover, author, contents, chapters and embedded raster images.
  DOMPurify sanitizes each section; publisher CSS, external resources and
  DRM are unsupported. Up to 12 sections are included, with omitted content
  labeled. See PLUGINS.md for the native size/time limits.
- `subtitles-model.mjs` parses SRT and WebVTT, including cue IDs, settings,
  speaker tags, multiline text and NOTE/STYLE/REGION blocks. The viewer adds
  search, transcript view, duration and 200-cue paging. It supports UTF-8 and
  BOM-marked UTF-16 through native text input. Limits: 10 MiB, 30,000 cues and
  20,000 characters per cue; malformed and truncated input is labeled.

`test/documents.test.mjs` covers these bundles, including hostile markup,
external resource removal, navigation, large lists and malformed timestamps.
`samples/make_documents.py` at the repository root generates native fixtures.

## Notebook

The `.ipynb` plugin uses JupyterLab's `@jupyterlab/rendermime` 4.6.4 rendering
functions, Marked for Markdown, highlight.js for code, KaTeX for math, and
DOMPurify for sanitization. Versions and transitive dependencies are locked.
It reads notebook formats 3 and 4 and never starts a kernel.

Supported saved output: streams, error tracebacks, HTML tables, PNG/JPEG/GIF/WebP,
SVG, Markdown, LaTeX, plain text and JSON. Markdown supports embedded raster
attachments. Python, JavaScript, TypeScript, R, Julia, Bash, SQL and JSON have
syntax highlighting; other languages display as plain code. Both themes work.
The preview has a code visibility toggle and collapses code longer than 24 lines.

Limits: 20 MiB files, up to 12 cells per page (fewer if rendering takes over
750 ms), 50 outputs per cell, 100,000 characters per text field and 8 MiB per
encoded image. Truncation is labeled. Oversized HTML falls back to plain text.
Widgets and JavaScript-only output need a saved static representation; the
preview never executes notebook code or fetches external images, links or files.

HTML is always untrusted, regardless of notebook metadata. DOMPurify removes
active markup, external URLs and styles. SVG is sanitized and used only as a
passive data-URI image. KaTeX uses `trust: false`. A page CSP and the host's
WebKit content rules block network access. The vendor directory is exempt from
the validator's URL-literal heuristic because libraries include inert URL
constants; first-party plugin code still gets that check. Tests cover hostile
markup and record attempts to call fetch, XHR or WebSocket while rendering.

`sanitize-html` is an unused transitive JupyterLab dependency, overridden to
2.18.1 to avoid vulnerable versions in the build dependency tree. DOMPurify is
the sanitizer used by this plugin.

The build collects licenses for packages whose code reaches the bundle. Some
upstream npm packages omit license files, so these copies are retained:

- `licenses/jupyterlab.txt`: [JupyterLab v4.6.4 LICENSE](https://github.com/jupyterlab/jupyterlab/blob/v4.6.4/LICENSE).
- `licenses/lumino.txt`: [Lumino LICENSE](https://github.com/jupyterlab/lumino/blob/main/LICENSE), downloaded 2026-10-19.
- `licenses/katex-fonts.txt`: copyright and reserved-name notices extracted from
  the unmodified KaTeX 0.19.0 TTF files, followed by the
  [SIL OFL 1.1](https://openfontlicense.org/documents/OFL.txt) text.

The build collects only the dependencies used by each entry point. Its
`vendor/THIRD_PARTY_LICENSES.txt` ships with that plugin. Markdown and notebook
also bundle KaTeX's fonts and their license notices.
