# shade / iLEmu

## 1. What this is

A from-scratch iOS/Darwin emulator. CMake project name is `iLEmu`
(`project(iLEmu ...)` in `CMakeLists.txt`); the built executable is `ilemu`.
It boots an ARM32 iPhoneOS userland (from an externally supplied, extracted
firmware rootfs — never checked in here) against a reimplemented Darwin/XNU
kernel personality (Mach, BSD, IOKit) running on Dynarmic, an ARM
recompiler/JIT vendored as the `external/dynarmic` submodule. The host side
renders through a software or Vulkan GLES path and displays via SDL2.

This repository builds and tests standalone; it does not itself contain
firmware images, device automation, or the surrounding workspace's
"emulator-lab" tooling. Its own commits (e.g. `29bcf3ec`, `c8de818c`) show it
being consumed as a package (`ilemu`) built and patched by a sibling repo
("Charon") elsewhere in this workspace — treat that relationship as
external; nothing in this repo's build depends on it.

## 2. Layout

- `CMakeLists.txt` — single entry point for the whole project (see §3).
- `src/<module>/` — one static library per module, each with its own
  `CMakeLists.txt` and `include/<module>/` public headers:
  - `foundation/` — the ARM CPU model on top of Dynarmic, address space,
    dyld shared cache, Mach-O loading, executable catalog, firmware
    preparation, JIT artifact/cache-governor code.
  - `kernel/` — the Darwin kernel personality, split into `mach/`
    (tasks, threads, ports, VM, scheduler), `bsd/` (VM, filesystem,
    network, process, signal, security, sysctl, device), and `iokit/`
    (hid, display, graphics, audio, camera, baseband, keybag, mbx, jpeg,
    mobile file integrity).
  - `device_state/` — Darwin identity/config state: firmware identity,
    kernel identity, lockdown, launchd job catalog, network preferences.
  - `graphics/` — the GLES rasterizer/renderer, boot logo, CoreAnimation
    remote ABI, LayerKit compatibility.
  - `mach/`, `filesystem/`, `network/`, `storage/`, `telephony/`, `media/`,
    `bluetooth/`, `crypto/`, `debug/`, `host/`, `runtime/` — one module
    each; `host/` is the only module gated on host libraries (ffmpeg for
    audio decode, native GLES).
- `app/` — the `ilemu` executable: CLI dispatch (`main.cpp`), the SDL2
  display/input/audio backend (`app/sdl/`), and live control
  (`app/control/`).
- `tools/` — `prepare_boot_logo.py` (host-side firmware asset prep via
  XPwn) and `tools/guest/` (an optional ARMv6 guest probe binary, built
  with a separate cctools-port linker, not part of the normal build).
- `external/` — `dynarmic` and `ext-boost` as git submodules (see
  `.gitmodules`); `vulkan-memory-allocator` is vendored directly (not a
  submodule) as an unmodified single header.
- No `tests/` directory exists in this repo. `CMakeLists.txt` looks for one
  at `ILEMU_TESTS_DIR` (default `<source>/tests`) and only wires it in via
  `add_subdirectory` if present under `BUILD_TESTING` — a surrounding
  workspace checkout can supply that tree without changing this file.

## 3. Build

```
git submodule update --init --recursive
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

Requires CMake ≥ 3.24, a C++20 compiler, and Threads. `external/dynarmic`
and `external/ext-boost` must be checked out first — CMake configure fails
fast (`FATAL_ERROR`) with a clear message if either is missing.

Optional, auto-detected through `find_package`/`pkg-config` and safe to be
absent:
- `ILEMU_ENABLE_SDL2` (default ON) — needs `sdl2` via pkg-config; without it
  `ilemu` builds but has no display backend.
- `ILEMU_ENABLE_VULKAN` (default ON) — needs the Vulkan SDK; falls back to
  the software GLES path if not found.
- `ffmpeg` (`libavformat`/`libavcodec`/`libavutil`/`libswresample`) and
  `libplist-2.0` via pkg-config, for audio decode and plist handling.

The resulting binary is `build/ilemu`. It is a CLI with subcommands, not a
GUI launcher — run `./build/ilemu help` for the full list. Two subcommands
need no firmware rootfs and are the right smoke check after a build:

```
./build/ilemu smoke
./build/ilemu benchmark arm
```

Everything else (`boot`, `inspect`, `catalog`, `firmware prepare`,
`disasm`, `abi`) takes `--rootfs DIR` pointing at an extracted iPhoneOS
firmware tree, which this repo does not provide or commit (see `.gitignore`:
`/firmwares/`, `/build/`, `/.cache-mem/`).

## 4. Conventions

- Commit subjects are lowercase, imperative, usually `<area>: Sentence.`
  where `<area>` is a module name (`mach:`, `kernel:`, `hid:`, `graphics:`,
  `memory:`, `iokit:`, `vm:`, `host:`, `runtime:`, ...) matching a `src/`
  subdirectory; a few commits (submodule bumps, patch imports) omit the
  prefix. No conventional-commit type prefixes (`feat:`, `fix:`).
- License is MPL-2.0; every source and CMake file opens with the standard
  MPL boilerplate comment — keep it on new files.
- `.clang-format` bases on WebKit style (brace/indent/pointer conventions),
  80-column limit, aligned operands, no forced operator-line breaks.
- `.gitignore` excludes `/build/`, `*.log`, `/firmwares/`, `/.cache-mem/`,
  `/tools/__pycache__/` — firmware dumps, logs, and build/cache output
  never belong in a commit here.
- New modules under `src/` need a matching `include/<module>/` root and a
  call to `ilemu_configure_module()` in their `CMakeLists.txt`, which wires
  the include path and (for `kernel/*` subtargets) the shared
  `iLEmu::kernel_api` interface.

## 5. Traps

- `ILEMU_ENABLE_IPO` (default ON) is not just an optimization toggle: the
  CMake comment notes startup time is dominated by Dynarmic's small IR and
  emission helpers, which IPO lets the compiler inline across library
  boundaries. Turning it off for a faster Release build will quietly
  regress JIT startup performance.
- Configuring the project runs `git apply` against the checked-out
  `external/dynarmic` submodule (a small iLEmu-specific test-emit-failure
  patch at `tools/dynarmic_ilemu_test_emit_failure.patch`), reversing it if
  already applied. Bumping the submodule to a revision the patch no longer
  applies cleanly to turns into a configure-time `FATAL_ERROR`, not a build
  failure — check that patch before updating `external/dynarmic`.
