#!/bin/zsh
# Builds the minimal LGPL FFmpeg for what Apple's decoders can't play:
# - MPEG-2 video (over-the-air ATSC 1.0 through an HDHomeRun; its decoder plays MPEG-1 too, for older
#   SD channels), with the mpegvideo parser and the bwdif deinterlacer;
# - AAC-LATM and Opus audio, with their parsers (the Opus decoder needs libswresample).
# Nothing else.
#
# Output: Frameworks/libavutil, libavcodec, libavfilter and libswresample.xcframework, each a dynamic
# framework for tvOS and iOS (arm64), their simulators and macOS (arm64 and x86_64: Xcode's generic
# simulator and Mac builds link both; macOS runs `swift test`). Dynamic, so a viewer can swap in their
# own build of the same libraries (LGPL 2.1, section 6).
# The device slices (tvOS, iOS) carry their dSYMs, so an archive has FFmpeg's debug symbols for App Store Connect's
# crash reports; simulator and Mac slices never reach it, so they go without (about 20 MB less in the repository).
#
# No --enable-gpl, --enable-version3 or --enable-nonfree: configure must report "LGPL version 2.1 or
# later", and the script stops if it doesn't. MPEG-2's last US patent expired on 13 February 2018.
#
# Usage: docs/tools/build_ffmpeg.sh            (sources and objects go to build/ffmpeg/, git-ignored)

set -euo pipefail

FFMPEG_VERSION=8.1.3
FFMPEG_SHA256=7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3
# Our build settings' revision: raise it whenever CONFIGURE_FLAGS change, so github.com/Demolasher/zapline-ffmpeg
# gets a new release (docs/tools/package_ffmpeg_source.sh). 1: Zapline 1.0 (3). 2: debug symbols, from 1.0 (4).
ZAPLINE_REVISION=2
MIN_OS=26.0
LIBS=(libavutil libswresample libavcodec libavfilter)

ROOT=${0:A:h:h:h}
WORK=$ROOT/build/ffmpeg
OUT=$ROOT/Frameworks
TARBALL=$WORK/ffmpeg-$FFMPEG_VERSION.tar.xz
SRC=$WORK/ffmpeg-$FFMPEG_VERSION

CONFIGURE_FLAGS=(
    --disable-everything --disable-autodetect --disable-programs --disable-doc --disable-network
    --disable-avformat --disable-avdevice --disable-swscale
    --enable-decoder=mpeg2video,aac_latm,opus --enable-parser=mpegvideo,aac_latm,opus
    --enable-filter=bwdif
    --enable-shared --disable-static --enable-pic --disable-stripping
)

mkdir -p "$WORK"
if [[ ! -f $TARBALL ]]; then
    curl -sSfL -o "$TARBALL" "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
fi
if [[ $(shasum -a 256 "$TARBALL" | cut -d' ' -f1) != $FFMPEG_SHA256 ]]; then
    echo "error: $TARBALL doesn't match the pinned SHA-256" >&2
    exit 1
fi
[[ -d $SRC ]] || tar -xJf "$TARBALL" -C "$WORK"

# FFmpeg's configure breaks on a space in its path ("maker portfolio"), so it works through a
# space-free link; the files stay in build/ffmpeg on this volume.
LINK_DIR=$(mktemp -d)
trap 'rm -rf "$LINK_DIR"' EXIT
ln -s "$WORK" "$LINK_DIR/ffmpeg"
WORK=$LINK_DIR/ffmpeg
SRC=$WORK/ffmpeg-$FFMPEG_VERSION

# platform name, SDK, target triple after the architecture, CFBundleSupportedPlatforms, architectures
PLATFORMS=(
    "tvos appletvos apple-tvos$MIN_OS AppleTVOS arm64"
    "tvsim appletvsimulator apple-tvos$MIN_OS-simulator AppleTVSimulator arm64 x86_64"
    "ios iphoneos apple-ios$MIN_OS iPhoneOS arm64"
    "iossim iphonesimulator apple-ios$MIN_OS-simulator iPhoneSimulator arm64 x86_64"
    "macos macosx apple-macos$MIN_OS MacOSX arm64 x86_64"
)

# $1 library, $2 version, $3 supported platform, $4 path
write_info_plist() {
    local minimum_key=MinimumOSVersion
    [[ $3 == MacOSX ]] && minimum_key=LSMinimumSystemVersion
    cat > "$4" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$1</string>
    <key>CFBundleIdentifier</key><string>org.ffmpeg.$1</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$1</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>$2</string>
    <key>CFBundleVersion</key><string>$2</string>
    <key>CFBundleSupportedPlatforms</key><array><string>$3</string></array>
    <key>$minimum_key</key><string>$MIN_OS</string>
</dict>
</plist>
PLIST
}

for entry in $PLATFORMS; do
    read -r name sdk target supported archs <<< "$entry"
    archs=(${=archs})
    for arch in $archs; do
        build=$WORK/build-$name-$arch
        prefix=$WORK/install-$name-$arch
        rm -rf "$build" "$prefix"
        mkdir -p "$build"
        # Intel slices only link and run tests, so they skip assembly (it needs nasm).
        asm=()
        [[ $arch == x86_64 ]] && asm=(--disable-x86asm)
        (
            cd "$build"
            # Cross-compiling for macOS too: configure then uses the system's cc, which finds the SDK, for its host tools.
            "$SRC/configure" --prefix="$prefix" --enable-cross-compile \
                --target-os=darwin --arch=${arch/arm64/aarch64} \
                --cc="$(xcrun -sdk $sdk -f clang)" --sysroot="$(xcrun -sdk $sdk --show-sdk-path)" \
                --extra-cflags="-target $arch-$target" \
                --extra-ldflags="-target $arch-$target -Wl,-headerpad_max_install_names" \
                --install-name-dir=@rpath \
                $asm $CONFIGURE_FLAGS > configure.log
            if ! grep -q "^License: LGPL version 2.1 or later" configure.log; then
                echo "error: the $name $arch build isn't LGPL 2.1 or later; see $build/configure.log" >&2
                exit 1
            fi
            make -j"$(sysctl -n hw.ncpu)" > make.log
            make install > install.log
        )
    done
    # Headers are the same for every architecture; take the first one's.
    prefix=$WORK/install-$name-${archs[1]}

    for lib in $LIBS; do
        dylib=$WORK/$lib-$name.dylib
        lipo -create $(for arch in $archs; do ls "$WORK/install-$name-$arch"/lib/$lib.*.*.*.dylib; done) -output "$dylib"
        version=$(ls "$prefix"/lib/$lib.*.*.*.dylib)
        version=${${version:t}#$lib.}
        version=${version%.dylib}
        fw=$WORK/frameworks-$name/$lib.framework
        rm -rf "$fw"
        if [[ $name == macos ]]; then
            # macOS frameworks are versioned bundles.
            mkdir -p "$fw/Versions/A/Headers" "$fw/Versions/A/Resources"
            cp "$dylib" "$fw/Versions/A/$lib"
            cp "$prefix"/include/$lib/*.h "$fw/Versions/A/Headers/"
            write_info_plist $lib $version $supported "$fw/Versions/A/Resources/Info.plist"
            ln -s A "$fw/Versions/Current"
            for item in $lib Headers Resources; do ln -s Versions/Current/$item "$fw/$item"; done
            binary=$fw/Versions/A/$lib
            install_dir=@rpath/$lib.framework/Versions/A
        else
            mkdir -p "$fw/Headers"
            cp "$dylib" "$fw/$lib"
            cp "$prefix"/include/$lib/*.h "$fw/Headers/"
            write_info_plist $lib $version $supported "$fw/Info.plist"
            binary=$fw/$lib
            install_dir=@rpath/$lib.framework
        fi
        install_name_tool -id "$install_dir/$lib" "$binary"
        # Point each dependency (@rpath/libavutil.60.dylib) at its framework.
        for dependency in $(otool -L "$binary" | awk '/@rpath\/lib.*\.dylib/ {print $1}'); do
            dependency_lib=${${dependency:t}%%.*}
            if [[ $name == macos ]]; then
                install_name_tool -change "$dependency" "@rpath/$dependency_lib.framework/Versions/A/$dependency_lib" "$binary"
            else
                install_name_tool -change "$dependency" "@rpath/$dependency_lib.framework/$dependency_lib" "$binary"
            fi
        done
        # Debug symbols before stripping: App Store Connect symbolicates crashes inside FFmpeg from the archive's
        # dSYMs, which Xcode copies from each xcframework's `-debug-symbols`. Stripping keeps the binary's UUID.
        dsym=$WORK/dsyms-$name/$lib.framework.dSYM
        rm -rf "$dsym"
        [[ $name == tvos || $name == ios ]] && dsymutil "$binary" -o "$dsym"
        strip -x "$binary"
        codesign --force --sign - "$binary" 2> /dev/null
    done
done

mkdir -p "$OUT"
for lib in $LIBS; do
    rm -rf "$OUT/$lib.xcframework"
    slices=()
    for entry in $PLATFORMS; do
        dsym=$WORK/dsyms-${entry%% *}/$lib.framework.dSYM
        slices+=(-framework "$WORK/frameworks-${entry%% *}/$lib.framework")
        [[ -d $dsym ]] && slices+=(-debug-symbols "$dsym")
    done
    xcodebuild -create-xcframework $slices -output "$OUT/$lib.xcframework" > /dev/null
done

echo "FFmpeg $FFMPEG_VERSION (LGPL 2.1 or later) built into $OUT:"
du -sh "$OUT"/*.xcframework
