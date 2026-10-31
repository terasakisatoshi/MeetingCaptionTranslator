#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_dir="$root/build/speech.cpp"
build_dir="$root/build/speech-native"
revision=af6b034918722b65c0f323d984d4644cd4120c77
if [ ! -d "$source_dir/.git" ]; then
    git clone --no-checkout https://github.com/nyosegawa/speech.cpp.git "$source_dir"
fi
git -C "$source_dir" fetch origin "$revision"
git -C "$source_dir" checkout --detach "$revision"
git -C "$source_dir" submodule update --init --recursive
cmake -S "$source_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=OFF
cmake --build "$build_dir" --target speech speech-cli --parallel 4
"$build_dir/speech" --version
