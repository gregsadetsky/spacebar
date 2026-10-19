# System libarchive bridge

Spacebar links the libarchive shipped with macOS; it does not bundle a second
copy. The macOS SDK exposes the library but not its C headers, so these public
headers are retained from libarchive v3.7.4:

- https://github.com/libarchive/libarchive/blob/v3.7.4/libarchive/archive.h
- https://github.com/libarchive/libarchive/blob/v3.7.4/libarchive/archive_entry.h

Their original BSD license notices are preserved in each file. The module map
is shared by SwiftPM and the direct `swiftc` build. The host uses only read
APIs; archive contents never get extracted onto the filesystem.
