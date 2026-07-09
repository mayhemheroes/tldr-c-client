#!/usr/bin/env bash
#
# mayhem/build.sh — build tldr-c-client's fuzz targets and its test build.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# (ghcr.io/mayhemheroes/base) already exports the build contract: CC, CXX, LIB_FUZZING_ENGINE,
# SANITIZER_FLAGS, DEBUG_FLAGS, STANDALONE_FUZZ_MAIN, SRC.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# NB: SANITIZER_FLAGS uses `=` (no colon) on purpose — an explicit EMPTY value
# (`--build-arg SANITIZER_FLAGS=`) is honored and builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

LIBS="-lcurl -lzip -lm"

# 1) TEST build first (project's NORMAL flags, no sanitizers) — stashed to out-test/ for
#    mayhem/test.sh, which only RUNS it. The obj/ tree is shared, so clean between builds.
make clean >/dev/null 2>&1 || true
make -j"$MAYHEM_JOBS" V=1 CC="$CC" LD="$CC" CFLAGS="-O2 $COVERAGE_FLAGS" LDFLAGS="$COVERAGE_FLAGS"
mkdir -p "$SRC/out-test"
cp ./tldr "$SRC/out-test/tldr"

# 2) SANITIZED project build — the fuzzed code itself is instrumented (ASan+UBSan halting)
#    and carries DWARF-3 debug info. ./tldr (= /mayhem/tldr) is the `tldr` file-input target.
make clean >/dev/null 2>&1 || true
make -j"$MAYHEM_JOBS" V=1 CC="$CC" LD="$CC" \
    CFLAGS="-O1 $SANITIZER_FLAGS $DEBUG_FLAGS" \
    LDFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS"

# 3) Fuzz objects: the fuzzed project code compiled with sanitizers AND libFuzzer
#    coverage instrumentation (-fsanitize=fuzzer-no-link) so the fuzzer sees edges.
#    tldr.c is excluded (it holds main()). parse_tldrpage() pulls in get_file_content
#    (local.c) etc., so link the whole non-main object set for the tldr harness.
FUZZ_CFLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -D_GNU_SOURCE"
for u in utils local net parser; do
    $CC $FUZZ_CFLAGS -I"$SRC/src" -c "$SRC/src/$u.c" -o "/tmp/${u}_fuzz.o"
done
# Standalone (run-once, non-fuzzer) driver — compiled as C so LLVMFuzzerTestOneInput keeps C linkage.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o

# rround libFuzzer target — fuzzes rround() in utils.c.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    "$SRC/mayhem/fuzz_rround.cpp" /tmp/utils_fuzz.o $LIBS -o "$SRC/fuzz_rround"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS \
    "$SRC/mayhem/fuzz_rround.cpp" /tmp/standalone_main.o /tmp/utils_fuzz.o $LIBS \
    -o "$SRC/fuzz_rround-standalone"

# tldr libFuzzer target — drives the page renderer/parser (parse_tldrpage) in-process.
TLDR_OBJS="/tmp/parser_fuzz.o /tmp/local_fuzz.o /tmp/net_fuzz.o /tmp/utils_fuzz.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
    "$SRC/mayhem/fuzz_tldr.cpp" $TLDR_OBJS $LIBS -o "$SRC/fuzz_tldr"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS \
    "$SRC/mayhem/fuzz_tldr.cpp" /tmp/standalone_main.o $TLDR_OBJS $LIBS \
    -o "$SRC/fuzz_tldr-standalone"

echo "build.sh: done"
ls -l "$SRC/out-test/tldr" "$SRC/fuzz_rround" "$SRC/fuzz_rround-standalone" \
      "$SRC/fuzz_tldr" "$SRC/fuzz_tldr-standalone"
