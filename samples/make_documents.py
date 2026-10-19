"""Generate local preview fixtures without third-party Python packages."""
import base64
import io
import json
import math
from pathlib import Path
import struct
import subprocess
import tarfile
import tempfile
import zipfile
import zlib

ROOT = Path(__file__).resolve().parent
def png_chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))

# An original geometric cover, encoded as a PNG with no graphics dependencies.
w, h = 240, 340
scanlines = bytearray()
for y in range(h):
    scanlines.append(0)
    for x in range(w):
        river = 120 + 32 * math.sin(y / 55)
        color = (26, 67, 67) if abs(x-river) > 25 else (113, 171, 157)
        if 25 < x < 215 and y in range(33, 37): color = (225, 208, 162)
        if 25 < x < 215 and y in range(303, 307): color = (225, 208, 162)
        scanlines.extend(color)
png = b'\x89PNG\r\n\x1a\n' + png_chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
png += png_chunk(b'IDAT', zlib.compress(bytes(scanlines))) + png_chunk(b'IEND', b'')

(ROOT / 'guide.md').write_text('''---
title: A field guide
author: Spacebar
---
# A field guide

Good notes make the next experiment easier. This document brings **ideas**, `code`, and results together.

## The plan

- Start with a small question.
- Write down what you expect.
- Compare the result with the prediction.

> A useful preview should make a document readable at a glance.

## A little code

```python
def average(values):
    return sum(values) / len(values)

average([2, 4, 6])
```

## Results

| Experiment | Samples | Result |
| --- | ---: | --- |
| Baseline | 120 | 3.8 |
| Revised | 180 | 4.2 |

The sample mean is $\\bar{x} = \\frac{1}{n}\\sum_{i=1}^{n}x_i$.

## Next steps

The next run will repeat the measurement with a larger sample.
''')
(ROOT / 'hostile.md').write_text('# Safe title\n\n<script>window.attacked=true</script><img src="https://example.com/pixel" onerror="window.attacked=true">\n\n[bad](javascript:alert(1))')
(ROOT / 'dialogue.srt').write_text('''1
00:00:01,200 --> 00:00:04,800
Welcome to the field station.

2
00:00:05,100 --> 00:00:08,500
<i>What are we looking for today?</i>

3
00:00:09,000 --> 00:00:14,200
Patterns in the water, the wind,
and everything in between.

4
00:00:15,000 --> 00:00:18,000
Let's start with the river. 🌊
''')
(ROOT / 'captions.vtt').write_text('''WEBVTT

NOTE This is a comment, not a cue.

intro
00:01.200 --> 00:04.800 align:start
<v Mira>Welcome to the field station.</v>

question
00:05.100 --> 00:08.500
<v Jules><i>What are we looking for today?</i></v>

answer
00:09.000 --> 00:14.200
<v Mira>Patterns in the water &amp; wind.</v>
''')
(ROOT / 'unicode.srt').write_bytes((ROOT / 'dialogue.srt').read_text().encode('utf-16'))
(ROOT / 'invalid.srt').write_text('1\n99:99:99,000 --> nonsense\nNo valid timestamps\n')
(ROOT / 'many-cues.srt').write_text('\n\n'.join(f'{i+1}\n00:{i//60:02}:{i%60:02},000 --> 00:{(i+1)//60:02}:{(i+1)%60:02},000\nSample cue {i+1}' for i in range(1000)))

files = {'Project/README.md': b'# Field notes\n', 'Project/data/measurements.csv': b'day,value\n1,3.8\n2,4.2\n',
         'Project/notes/Ideas.txt': b'Follow the river upstream.\n', 'Project/notes/世界.txt': 'Hello 世界\n'.encode(),
         'Images/pixel.png': png}
with zipfile.ZipFile(ROOT / 'project.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for name, data in files.items():
        info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 12, 0, 0)); info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, data)
    archive.writestr('Empty/', b'')
with zipfile.ZipFile(ROOT / 'empty.zip', 'w'): pass
with zipfile.ZipFile(ROOT / 'unusual-paths.zip', 'w') as archive:
    archive.writestr('../outside.txt', b'Never extracted')
    archive.writestr('/absolute.txt', b'Never extracted')
    archive.writestr('<script>alert(1)</script>.txt', b'Literal filename')
for name, mode in [('project.tar', 'w'), ('project.tar.gz', 'w:gz')]:
    with tarfile.open(ROOT / name, mode) as archive:
        for path, data in files.items():
            info = tarfile.TarInfo(path); info.size = len(data); info.mtime = 1767268800
            archive.addfile(info, io.BytesIO(data))
        info = tarfile.TarInfo('Project/latest'); info.type = tarfile.SYMTYPE; info.linkname = 'notes/Ideas.txt'; archive.addfile(info)
with tempfile.TemporaryDirectory() as temporary:
    for path, data in files.items():
        target = Path(temporary) / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(data)
    subprocess.run(['/usr/bin/tar', '-c', '--format', '7zip', '-f', str(ROOT / 'project.7z'), '-C', temporary, 'Project', 'Images'], check=True)

# A tiny RAR 4 store-only fixture. Header layout follows RAR's public file
# format; CRCs cover the header bytes following HEAD_CRC.
def rar_header(kind, flags, body):
    header = struct.pack('<BHH', kind, flags, 7 + len(body)) + body
    return struct.pack('<H', zlib.crc32(header) & 0xffff) + header
name = b'hello.txt'; data = b'Hello from a RAR archive.\n'
rar = b'Rar!\x1a\x07\x00' + rar_header(0x73, 0, bytes(6))
file_header = struct.pack('<IIBIIBBHI', len(data), len(data), 3, zlib.crc32(data), 0, 20, 0x30, len(name), 0o100644) + name
rar += rar_header(0x74, 0x8000, file_header) + data + rar_header(0x7b, 0x4000, b'')
(ROOT / 'project.rar').write_bytes(rar)
(ROOT / 'invalid.zip').write_text('Not an archive')

container = '<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="Book/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'
opf = '''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>The Field Notebook</dc:title><dc:creator>Mira Rivers</dc:creator><dc:language>en</dc:language><dc:identifier id="id">urn:spacebar:sample</dc:identifier></metadata><manifest><item id="one" href="chapters/one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="chapters/two.xhtml" media-type="application/xhtml+xml"/><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>'''
nav = '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="chapters/one.xhtml">1. Along the river</a></li><li><a href="chapters/two.xhtml">2. A change in the weather</a></li></ol></nav></body></html>'
chapter1 = '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Along the river</h1><p>We arrived before sunrise, when the water still held the last blue of the night. The station was quiet except for a kettle beginning to boil.</p><p>Mira opened her notebook. On the first page she had written a question: <em>What changes when we pay attention?</em></p><p>Outside, the river made its slow turn through the valley. We packed the instruments and walked down to the bank.</p><h2>The first measurement</h2><p>The thermometer read twelve degrees. We wrote it down, alongside the time and the direction of the wind.</p><p><a href="two.xhtml">Continue to the next chapter</a></p></body></html>'
chapter2 = '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>A change in the weather</h1><p>By noon the clouds had crossed the ridge. Every measurement told a slightly different story.</p><p>We would return tomorrow, and the day after that. A pattern takes time to reveal itself.</p><img src="../cover.png" alt="Field illustration"/></body></html>'
for filename, malicious in [('field-notebook.epub', False), ('untrusted.epub', True)]:
    with zipfile.ZipFile(ROOT / filename, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('mimetype', b'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        archive.writestr('META-INF/container.xml', container); archive.writestr('Book/package.opf', opf)
        archive.writestr('Book/nav.xhtml', nav); archive.writestr('Book/cover.png', png)
        archive.writestr('Book/chapters/one.xhtml', chapter1 if not malicious else '<html xmlns="http://www.w3.org/1999/xhtml"><body><h1>Safe text</h1><script>window.attacked=true</script><img src="https://example.com/pixel" onerror="window.attacked=true"/><iframe src="file:///etc/passwd"></iframe></body></html>')
        archive.writestr('Book/chapters/two.xhtml', chapter2)
with zipfile.ZipFile(ROOT / 'invalid.epub', 'w') as archive: archive.writestr('readme.txt', 'Not a book')
print('documents: Markdown, ZIP/TAR/TAR.GZ/7z/RAR, EPUB, SRT/WebVTT and error cases')
