# ObfuscationRepo

The xmake package repository for Obfuscation Project components.

## SysToolchain

`systoolchain 0.1.0` supplies one relocatable GCC 14.2.0/Binutils 2.42
freestanding toolchain plus its matching QEMU 10.2.0 system emulator (with
pinned DTC 1.6.1) per target architecture. Register this repository and attach
the package to xmake's generic cross toolchain:

```lua
add_repositories("obfuscation https://github.com/ObfuscationProject/ObfuscationRepo.git")
add_requires("systoolchain 0.1.0", {system = false})

target("kernel")
    set_kind("binary")
    set_toolchains("cross@systoolchain")
    add_files("src/*.c", "src/*.cpp")
```

Configure the consumer with its target architecture, for example:

```sh
xmake f -c -y -a x86_64
xmake -y
```

By default the package downloads the matching Linux x86_64 host archive from
the [SysToolchain releases](https://github.com/ObfuscationProject/SysToolchain/releases)
and verifies the adjacent `.sha256` file before installation. Supported targets
are `i386`, `x86_64`, `aarch64`, `arm32`, `rv64`, `rv32`, `loongarch64`,
`mips`, `mips64`, and `ppc` (including the aliases documented by
SysToolchain).

Package installation validates the build manifest, licenses, relocation-safe
links, the complete compiler/binutils program set, C++ runtime archives, C/C++
compilation and linking, and QEMU version/machine/display/data capabilities.
Consumers therefore do not need a separate `toolchain-check` task.

Set `build_from_source=true` to invoke SysToolchain's Lua/xmake builder instead:

```lua
add_requires("systoolchain 0.1.0", {
    system = false,
    configs = {build_from_source = true}
})
```

Source builds support Linux and macOS. `SYSTOOLCHAIN_JOBS`,
`SYSTOOLCHAIN_SOURCE_CACHE`, and `SYSTOOLCHAIN_BUILD_CACHE` control the nested
build. For local package development, `SYSTOOLCHAIN_SOURCE_ARCHIVE` can point
at a SysToolchain source archive and `SYSTOOLCHAIN_BINARY_MIRROR` can point at
a directory containing release assets and their `.sha256` files.
