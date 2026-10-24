# ObfuscationRepo plan

ObfuscationRepo publishes the xmake package recipes consumed by ObfuscationKernel
and ObfuscationOS. Changes here follow SysToolchain releases.

## 1. Verify the download path once `v0.1.0` exists

The recipe prefers the GitHub Release archive and verifies the adjacent
`.sha256`. On 2026-10-25 the path was exercised with `SYSTOOLCHAIN_BINARY_MIRROR`
pointing at the ten archives built in the release environment: the package
installed and passed its own test for every target, and all ten kernel profiles
passed `xmake test` with `build_from_source = false`. Repeat once against the
published `v0.1.0` assets on a clean host and record the result. The
source-build fallback now uses the host GLib, Pixman and SDL2 development files
instead of static xmake-repo builds.

## 2. `systoolchain 0.2.0`

Add the `<arch>-linux-musl` hosted toolchain family as a package config, for
example `configs = {family = "musl"}`, keeping the `*-elf` default. The OS
`feat/musl-primary` worktree selects it for userland targets only.

## 3. Host tool packages

- `e2fsprogs 1.47.2`: `mke2fs`, `tune2fs`, `e2fsck`, `debugfs` for rootfs image
  generation and verification, replacing the pinned Linux kernel image that the
  OS currently needs to activate a journal.
- `mtools` for FAT media checks, if the host package proves unreliable in CI.

## 4. Repository hygiene

- Add a CI job that runs `xmake l` against each recipe and the consumer fixture
  on every push, so a recipe change cannot break both product repositories at
  once.
