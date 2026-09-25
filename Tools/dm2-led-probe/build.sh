#!/bin/sh
# Builds dm2-led-probe (universal, macOS 11.0+) into build.noindex/ and copies it next to this script.
set -e
cd "$(dirname "$0")"
mkdir -p build.noindex
clang -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
	-o build.noindex/dm2-led-probe main.m legacy.c \
	-framework Foundation -framework IOKit -framework IOUSBHost -framework CoreFoundation
cp build.noindex/dm2-led-probe .
echo "built: $(pwd)/dm2-led-probe"
