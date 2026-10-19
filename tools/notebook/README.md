# Notebook renderer

The `.ipynb` plugin uses JupyterLab's `@jupyterlab/rendermime` 4.6.4 rendering
functions, Marked for Markdown, highlight.js for code, KaTeX for math, and
DOMPurify for sanitization. Versions and transitive dependencies are locked.
It reads notebook formats 3 and 4 and never starts a kernel.

Source lives here; the generated, offline bundle lives in
`plugins/notebook/vendor`. Normal app builds use that checked-in bundle and
do not need Node or a download. To change the renderer (Node 22):

```sh
npm ci --prefix tools/notebook --ignore-scripts
npm run build --prefix tools/notebook
npm test --prefix tools/notebook
make samples
make install
```

Commit the source, lockfile, and regenerated vendor files together. CI rebuilds
the bundle, checks that it matches the committed files, and tests the actual
bundle in jsdom. `make test` covers the native host and manifests; `make smoke`
also previews notebook fixtures through the real Quick Look extension.

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

The resulting `vendor/THIRD_PARTY_LICENSES.txt` ships with the plugin.
