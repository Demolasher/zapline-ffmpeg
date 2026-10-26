# zapline-ffmpeg

This software uses libraries from the FFmpeg project under the LGPLv2.1.

Zapline, Paper Lantern's live TV app, uses FFmpeg 8.1.3, unmodified, to play MPEG-2 video and AAC-LATM and
Opus sound, which Apple TV can't decode itself. FFmpeg belongs to its developers ([ffmpeg.org](https://ffmpeg.org)),
not to Paper Lantern. This repository holds its source exactly as Zapline ships it, and how it's built.

## What's here

- **The source:** [Releases](https://github.com/Demolasher/zapline-ffmpeg/releases) ›
  `ffmpeg-8.1.3-zapline.tar.xz`, FFmpeg's own release tarball, unmodified, with `BUILD.txt` added at its root.
- **`BUILD.txt`:** the version, the SHA-256 of FFmpeg's tarball, the configure line and the platforms.
- **`docs/tools/build_ffmpeg.sh`:** the script that builds the libraries.
- **`LICENSE`:** the GNU Lesser General Public License, version 2.1, as FFmpeg ships it (`COPYING.LGPLv2.1`).

## The build

- FFmpeg 8.1.3 from <https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz>, SHA-256 `7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3`. No patches.
- Only the MPEG-2 video decoder (it plays MPEG-1 too), the AAC-LATM and Opus decoders, their parsers and the bwdif
  deinterlacer. No `--enable-gpl`, `--enable-version3` or `--enable-nonfree`: configure reports
  "License: LGPL version 2.1 or later".
- libavutil libswresample libavcodec libavfilter, as dynamic frameworks for tvOS, iOS, their simulators and macOS.

## Rebuild it

On a Mac with Xcode:

```sh
git clone https://github.com/Demolasher/zapline-ffmpeg.git
cd zapline-ffmpeg
docs/tools/build_ffmpeg.sh
```

The script downloads FFmpeg's tarball, checks its SHA-256 and builds every platform into `Frameworks/` as
`.xcframework`s. The libraries are dynamic frameworks inside `Zapline.app/Frameworks`, so you can build your own
from this source and use them in their place.

Questions about this build: open an issue here.
