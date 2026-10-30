#!/bin/bash
# Native macOS build host; produces x86_64 LGPL-only shared libraries for Rosetta.
set -euo pipefail
version=7.1.3
sha=f0bf043299db9e3caacb435a712fc541fbb07df613c4b893e8b77e67baf3adbe
prefix=${FFMPEG_PREFIX:-$HOME/nectarine-deps/ffmpeg}
scratch=${FFMPEG_SCRATCH:-$HOME/nectarine-deps/ffmpeg-src}
mkdir -p "$scratch" "$prefix/share/licenses/ffmpeg"
archive="$scratch/ffmpeg-$version.tar.xz"
if [ ! -f "$archive" ]; then
    curl -fLsS "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" -o "$archive"
fi
echo "$sha  $archive" | shasum -a 256 -c -
if [ ! -d "$scratch/ffmpeg-$version" ]; then tar -xf "$archive" -C "$scratch"; fi
mkdir -p "$scratch/build"
cd "$scratch/build"
# No external codecs, encoders, networking, GPU APIs or GPL/nonfree code.
# Inline assembly remains enabled; standalone x86 assembly needs optional NASM.
"$scratch/ffmpeg-$version/configure" \
    --prefix="$prefix" --arch=x86_64 --target-os=darwin --enable-cross-compile \
    --cc='clang -arch x86_64' --cxx='clang++ -arch x86_64' \
    --extra-ldflags=-Wl,-headerpad_max_install_names --disable-x86asm \
    --disable-autodetect --disable-everything --disable-programs --disable-doc \
    --disable-static --enable-shared --disable-gpl --disable-nonfree \
    --disable-avdevice --enable-avfilter --disable-postproc \
    --enable-avcodec --enable-avformat --enable-avutil --enable-swresample --enable-swscale \
    --enable-decoder=h264,hevc,vp8,vp9,mpeg1video,mpeg2video,mpeg4,wmv1,wmv2,wmv3,vc1,wmav1,wmav2,wmapro,wmalossless,aac,mp3,vorbis,opus,bink,binkaudio_dct,binkaudio_rdft,pcm_s16le,pcm_s16be,pcm_u8,adpcm_ms,adpcm_ima_wav \
    --enable-demuxer=asf,mov,matroska,avi,bink,ogg,wav,mp3,aac,mpegps,mpegts,h264,hevc \
    --enable-parser=h264,hevc,vp8,vp9,mpegvideo,mpeg4video,vc1,aac,mpegaudio,vorbis,opus \
    --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,extract_extradata,null \
    --enable-filter=aresample,format,scale,buffer,buffersink,abuffer,abuffersink \
    --enable-protocol=file > configure-summary.txt
make -j"${JOBS:-6}" > build.log 2>&1
make install > install.log 2>&1
cp "$scratch/ffmpeg-$version"/COPYING.LGPLv2.1 "$scratch/ffmpeg-$version"/LICENSE.md "$prefix/share/licenses/ffmpeg/"
cp "$archive" "$prefix/share/licenses/ffmpeg/"
cp "$0" "$prefix/share/licenses/ffmpeg/build-ffmpeg.mac.sh"
cp config.h config_components.h ffbuild/config.mak configure-summary.txt "$prefix/share/licenses/ffmpeg/"
printf '%s\n' "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" "$sha" > "$prefix/share/licenses/ffmpeg/SOURCE"
if ! grep -q '^#define CONFIG_GPL 0$' config.h || ! grep -q '^#define CONFIG_NONFREE 0$' config.h; then
    echo 'Unexpected FFmpeg license configuration' >&2; exit 1
fi
file "$prefix/lib/libavcodec.dylib"
