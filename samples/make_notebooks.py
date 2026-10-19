"""Deterministic saved notebooks; no Python packages or kernel required."""
import base64
import json
import math
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parent


def write(name, value):
    (ROOT / f"{name}.ipynb").write_text(json.dumps(value, ensure_ascii=False, indent=1) + "\n")


def notebook(cells):
    return {"nbformat": 4, "nbformat_minor": 5, "metadata": {
        "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
        "language_info": {"name": "python", "version": "3.13"}}, "cells": cells}


def md(source, **extra):
    return {"cell_type": "markdown", "id": f"md-{len(source)}", "metadata": {}, "source": source, **extra}


def code(source, count, outputs):
    return {"cell_type": "code", "id": f"code-{count}", "metadata": {}, "source": source,
            "execution_count": count, "outputs": outputs}


def display(data):
    return {"output_type": "display_data", "metadata": {}, "data": data}


# A real PNG saved output, drawn with the standard library alone.
w, h = 640, 210
pixels = bytearray([255] * (w * h * 3))


def dot(x, y, color):
    if 0 <= x < w and 0 <= y < h:
        at = (y * w + x) * 3
        pixels[at:at + 3] = bytes(color)


for y in range(30, 181, 30):
    for x in range(40, 621):
        dot(x, y, (225, 230, 235))
for x in range(40, 621):
    y = round(105 - 65 * math.sin((x - 40) / 580 * math.pi * 2))
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            dot(x + dx, y + dy, (36, 119, 210))
for x in range(40, 621):
    dot(x, 180, (120, 130, 140))
for y in range(20, 181):
    dot(40, y, (120, 130, 140))


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


raw = b"".join(b"\0" + pixels[y * w * 3:(y + 1) * w * 3] for y in range(h))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
image = base64.b64encode(png).decode()
svg = '<svg xmlns="http://www.w3.org/2000/svg" width="640" height="100" viewBox="0 0 640 100"><rect width="640" height="100" fill="white"/><rect x="24" y="20" width="180" height="20" rx="4" fill="#2477d2"/><rect x="24" y="55" width="300" height="20" rx="4" fill="#31a370"/><text x="220" y="35" font-family="sans-serif" font-size="14">baseline</text><text x="340" y="70" font-family="sans-serif" font-size="14">experiment</text></svg>'

cells = [
    md("# A small experiment\n\nA notebook is a story told with **code, data, and pictures**. This preview shows the results saved in the file.\n\nFor a periodic signal, $y = \\sin(x)$ and $T = 2\\pi$."),
    code('import numpy as np\nimport pandas as pd\n\nx = np.linspace(0, 2 * np.pi, 100)\ny = np.sin(x)', 1, []),
    code('pd.DataFrame({"sample": x[:3], "signal": y[:3]}).round(3)', 2, [{
        "output_type": "execute_result", "execution_count": 2, "metadata": {}, "data": {
            "text/plain": "   sample  signal\n0   0.000   0.000\n1   0.063   0.063\n2   0.127   0.127",
            "text/html": '<table class="dataframe"><thead><tr><th></th><th>sample</th><th>signal</th></tr></thead><tbody><tr><th>0</th><td>0.000</td><td>0.000</td></tr><tr><th>1</th><td>0.063</td><td>0.063</td></tr><tr><th>2</th><td>0.127</td><td>0.127</td></tr></tbody></table>'}}]),
    code('import matplotlib.pyplot as plt\nplt.plot(x, y)\nplt.show()', 3, [display({"image/png": image, "text/plain": "<Figure with 1 Axes>"})]),
    md("## Saved outputs\n\nTables, plots, formulas, and logs remain readable without running the notebook.\n\n$$\\int_0^{2\\pi} \\sin(x)\\,dx = 0$$"),
    code('print("Loaded 100 samples ✓")', 4, [{"output_type": "stream", "name": "stdout", "text": ["\u001b[32mLoaded 100 samples ✓\u001b[0m\n"]}]),
    code('display(comparison_chart)', 5, [display({"image/svg+xml": svg})]),
    md("An image attached to a Markdown cell:\n\n![Signal](attachment:signal.png)", attachments={"signal.png": {"image/png": image}}),
    code('raise ValueError("Example of a saved traceback")', 6, [{"output_type": "error", "ename": "ValueError", "evalue": "Example of a saved traceback", "traceback": ["\u001b[31mValueError\u001b[0m: Example of a saved traceback"]}]),
    {"cell_type": "raw", "id": "raw", "metadata": {}, "source": "Raw notes are displayed as plain text: <not HTML>."},
]
write("analysis", notebook(cells))
write("empty", notebook([]))
write("large-notebook", notebook([code(f"print({i})", i, [{"output_type": "stream", "name": "stdout", "text": f"{i}\n"}]) for i in range(1000)]))
write("legacy-notebook", {"nbformat": 3, "nbformat_minor": 0, "metadata": {}, "worksheets": [{"cells": [
    {"cell_type": "heading", "level": 1, "source": "Legacy notebook"},
    {"cell_type": "code", "input": ["1 + 1"], "prompt_number": 1, "outputs": [{"output_type": "pyout", "text": ["2"], "prompt_number": 1}]}]}]})
write("invalid-notebook", {"nbformat": 4, "cells": [None]})
attack = '<script>window.notebookAttack=true</script><img src="https://example.com/pixel" onerror="window.notebookAttack=true"><iframe src="https://example.com"></iframe><p>Only this saved text should appear.</p>'
write("untrusted-notebook", notebook([md(attack), code("# This code must never execute", 1, [display({"text/html": attack}), display({"application/javascript": "window.notebookAttack=true"})])]))
print("notebooks: analysis, empty, large, legacy, invalid, untrusted")
