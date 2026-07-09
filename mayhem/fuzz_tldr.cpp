// In-process harness for the tldr page renderer/parser.
//
// The `tldr -r <file>` path reads a page file and hands its contents to
// parse_tldrpage() (src/parser.c) — the markdown-ish renderer. Fuzzing the raw
// binary via a file is unproductive because get_file_content() (src/local.c)
// reads the file into a buffer with no trailing NUL while parse_tldrpage() runs
// strlen() over it, so ANY input aborts on iteration #1 (heap-buffer-overflow)
// before any coverage is collected. This harness drives the same parser directly
// on a NUL-terminated copy of the fuzz input, so the renderer is exercised
// productively (and parser-level defects remain reachable).
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern "C" int parse_tldrpage(char const *input, int color_enabled);

// parse_tldrpage() renders to stdout; redirect it to a scratch sink so the fuzzer
// isn't flooded. Each iteration rewinds the sink (see below), so it stays bounded.
extern "C" int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void)argc; (void)argv;
    if (!freopen("/tmp/tldr_render.sink", "w", stdout)) { /* keep going if it fails */ }
    return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    char *buf = (char *)malloc(size + 1);
    if (buf == NULL)
        return 0;
    memcpy(buf, data, size);
    buf[size] = '\0';

    // Discard rendered output: rewind the sink so it never grows unbounded.
    fseek(stdout, 0, SEEK_SET);

    // Exercise both the color and no-color rendering branches.
    parse_tldrpage(buf, 1);
    parse_tldrpage(buf, 0);
    fflush(stdout);

    free(buf);
    return 0;
}
