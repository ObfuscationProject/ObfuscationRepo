# ObfuscationRepo plan

ObfuscationRepo publishes the xmake package recipes consumed by ObfuscationKernel
and ObfuscationOS. Changes here follow SysToolchain releases.

## 1. Verify the download path once `v0.1.0` exists

The recipe already prefers the GitHub Release archive and verifies the adjacent
`.sha256`. After SysToolchain publishes `v0.1.0`, run the consumer fixture
(`SysToolchain/tests/consumer`) with `build_from_source = false` on a clean
host and record the result; then the kernel and OS flip their defaults.

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
