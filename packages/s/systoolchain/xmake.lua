package("systoolchain")
    set_kind("toolchain")
    set_homepage("https://github.com/ObfuscationProject/SysToolchain")
    set_description("Relocatable GCC/Binutils toolchains and QEMU emulators for ObfuscationOS targets")
    set_license("GPL-3.0-or-later")

    local target_triples = {
        i386 = "i386-elf",
        x86 = "i386-elf",
        x86_64 = "x86_64-elf",
        x64 = "x86_64-elf",
        amd64 = "x86_64-elf",
        aarch64 = "aarch64-elf",
        arm64 = "aarch64-elf",
        arm32 = "arm-none-eabi",
        arm = "arm-none-eabi",
        rv64 = "riscv64-elf",
        riscv64 = "riscv64-elf",
        rv32 = "riscv32-elf",
        riscv32 = "riscv32-elf",
        loongarch64 = "loongarch64-elf",
        loong64 = "loongarch64-elf",
        mips = "mips-elf",
        mips64 = "mips64-elf",
        ppc = "powerpc-eabi",
        powerpc = "powerpc-eabi"
    }

    local canonical_arches = {
        "i386", "x86_64", "aarch64", "arm32", "rv64", "rv32",
        "loongarch64", "mips", "mips64", "ppc"
    }

    local qemu_systems = {
        ["i386-elf"] = "qemu-system-i386",
        ["x86_64-elf"] = "qemu-system-x86_64",
        ["aarch64-elf"] = "qemu-system-aarch64",
        ["arm-none-eabi"] = "qemu-system-arm",
        ["riscv64-elf"] = "qemu-system-riscv64",
        ["riscv32-elf"] = "qemu-system-riscv32",
        ["loongarch64-elf"] = "qemu-system-loongarch64",
        ["mips-elf"] = "qemu-system-mips",
        ["mips64-elf"] = "qemu-system-mips64",
        ["powerpc-eabi"] = "qemu-system-ppc"
    }

    local qemu_targets = {
        ["i386-elf"] = "i386-softmmu",
        ["x86_64-elf"] = "x86_64-softmmu",
        ["aarch64-elf"] = "aarch64-softmmu",
        ["arm-none-eabi"] = "arm-softmmu",
        ["riscv64-elf"] = "riscv64-softmmu",
        ["riscv32-elf"] = "riscv32-softmmu",
        ["loongarch64-elf"] = "loongarch64-softmmu",
        ["mips-elf"] = "mips-softmmu",
        ["mips64-elf"] = "mips64-softmmu",
        ["powerpc-eabi"] = "ppc-softmmu"
    }

    local target_arches = {
        ["i386-elf"] = "i386",
        ["x86_64-elf"] = "x86_64",
        ["aarch64-elf"] = "aarch64",
        ["arm-none-eabi"] = "arm32",
        ["riscv64-elf"] = "rv64",
        ["riscv32-elf"] = "rv32",
        ["loongarch64-elf"] = "loongarch64",
        ["mips-elf"] = "mips",
        ["mips64-elf"] = "mips64",
        ["powerpc-eabi"] = "ppc"
    }

    local configured_triple
    for arch, triple in pairs(target_triples) do
        if is_arch(arch) then
            configured_triple = triple
            break
        end
    end

    add_configs("triple", {
        description = "Canonical freestanding target triple",
        default = configured_triple,
        type = "string",
        readonly = true
    })
    add_configs("build_from_source", {
        description = "Build GCC/Binutils/QEMU locally through SysToolchain instead of downloading a release",
        default = false,
        type = "boolean"
    })
    add_configs("host_platform", {
        description = "Host platform used by the toolchain executables",
        default = os.host(),
        type = "string",
        readonly = true
    })
    add_configs("host_arch", {
        description = "Host architecture used by the toolchain executables",
        default = os.arch(),
        type = "string",
        readonly = true
    })

    -- This override makes an unpublished working tree testable. Normal
    -- consumers fetch the immutable SysToolchain tag. The separately fetched
    -- binary payload is always verified against its release .sha256 file.
    if on_source then
        on_source(function (package)
            local source_archive = os.getenv("SYSTOOLCHAIN_SOURCE_ARCHIVE")
            if source_archive and source_archive ~= "" then
                package:set("urls", path.absolute(source_archive))
            else
                package:set("urls", "https://github.com/ObfuscationProject/SysToolchain.git")
                package:add("versions", "0.1.0", "v0.1.0")
            end
        end)
    else
        local source_archive = os.getenv("SYSTOOLCHAIN_SOURCE_ARCHIVE")
        if source_archive and source_archive ~= "" then
            set_urls(path.absolute(source_archive))
        else
            set_urls("https://github.com/ObfuscationProject/SysToolchain.git")
            add_versions("0.1.0", "v0.1.0")
        end
    end

    local function normalized_host_arch(host_arch)
        local arch = host_arch
        if arch == "x64" or arch == "amd64" then
            return "x86_64"
        end
        if arch == "arm64" then
            return "aarch64"
        end
        return arch
    end

    local function target_triple(package)
        local arch = (package:targetarch() or package:arch() or ""):lower()
        return package:config("triple") or target_triples[arch], arch
    end

    local function supported_arches_message()
        return table.concat(canonical_arches, ", ")
    end

    local function source_root(directory, modules)
        if modules.os.isfile(modules.path.join(directory, "xmake.lua")) and
           modules.os.isdir(modules.path.join(directory, "xmake", "modules", "systoolchain")) then
            return directory
        end
        for _, subdirectory in ipairs(modules.os.dirs(modules.path.join(directory, "*"))) do
            if modules.os.isfile(modules.path.join(subdirectory, "xmake.lua")) and
               modules.os.isdir(modules.path.join(subdirectory, "xmake", "modules", "systoolchain")) then
                return subdirectory
            end
        end
        return nil
    end

    local function check(value, fail, message, ...)
        if not value then
            fail(message, ...)
        end
        return value
    end

    local function copy_or_download(url, output, modules)
        if modules.os.isfile(url) then
            modules.os.vcp(url, output)
            return
        end
        modules.http.download(url, output)
    end

    local function install_release(package, triple, modules, fail)
        check(modules.os.host() == "linux" and normalized_host_arch(modules.os.arch()) == "x86_64", fail,
            "package(%s): prebuilt releases currently support only Linux x86_64 hosts; " ..
            "set build_from_source=true on this host", package:name())

        local version = package:version_str()
        local asset = string.format("systoolchain-%s-linux-x86_64-%s.tar.xz", version, triple)
        local mirror = modules.os.getenv("SYSTOOLCHAIN_BINARY_MIRROR")
        local baseurl = modules.os.getenv("SYSTOOLCHAIN_RELEASE_BASEURL")
        if not baseurl or baseurl == "" then
            baseurl = string.format(
                "https://github.com/ObfuscationProject/SysToolchain/releases/download/v%s", version)
        end

        local release_dir = modules.path.join(package:builddir(), "systoolchain-release")
        local archivefile = modules.path.join(release_dir, asset)
        local checksumfile = archivefile .. ".sha256"
        local unpackdir = modules.path.join(release_dir, "unpacked")
        modules.os.tryrm(release_dir)
        modules.os.mkdir(release_dir)

        if mirror and mirror ~= "" then
            copy_or_download(modules.path.join(modules.path.absolute(mirror), asset), archivefile, modules)
            copy_or_download(modules.path.join(modules.path.absolute(mirror), asset .. ".sha256"), checksumfile, modules)
        else
            copy_or_download(baseurl .. "/" .. asset, archivefile, modules)
            copy_or_download(baseurl .. "/" .. asset .. ".sha256", checksumfile, modules)
        end

        local expected = modules.io.readfile(checksumfile):match("^%s*([0-9a-fA-F]+)")
        check(expected, fail, "package(%s): malformed checksum file for %s", package:name(), asset)
        expected = expected:lower()
        check(#expected == 64, fail, "package(%s): malformed SHA-256 for %s", package:name(), asset)
        local actual = modules.hash.sha256(archivefile):lower()
        check(actual == expected, fail,
            "package(%s): checksum mismatch for %s (expected %s, got %s)",
            package:name(), asset, expected, actual)

        modules.archive.extract(archivefile, unpackdir)
        local root = unpackdir
        if not modules.os.isfile(modules.path.join(root, "bin", triple .. "-gcc")) then
            for _, candidate in ipairs(modules.os.dirs(modules.path.join(unpackdir, "*"))) do
                if modules.os.isfile(modules.path.join(candidate, "bin", triple .. "-gcc")) then
                    root = candidate
                    break
                end
            end
        end
        check(modules.os.isfile(modules.path.join(root, "bin", triple .. "-gcc")), fail,
            "package(%s): %s does not contain bin/%s-gcc", package:name(), asset, triple)
        check(modules.os.isfile(modules.path.join(root, "bin", qemu_systems[triple])), fail,
            "package(%s): %s does not contain bin/%s", package:name(), asset, qemu_systems[triple])
        modules.os.vcp(modules.path.join(root, "*"), package:installdir())
    end

    local function install_from_source(package, triple, arch, modules, fail)
        check(modules.os.host() == "linux" or modules.os.host() == "macosx", fail,
            "package(%s): source builds require a Linux or macOS host", package:name())
        local root = source_root(modules.os.curdir(), modules)
        check(root, fail, "package(%s): cannot locate the SysToolchain source root", package:name())
        local argv = {
            "build-toolchain",
            "--arch=" .. arch,
            "--prefix=" .. package:installdir()
        }
        local jobs = modules.os.getenv("SYSTOOLCHAIN_JOBS")
        local source_cache = modules.os.getenv("SYSTOOLCHAIN_SOURCE_CACHE")
        local build_cache = modules.os.getenv("SYSTOOLCHAIN_BUILD_CACHE")
        if jobs and jobs ~= "" then
            table.insert(argv, "--jobs=" .. jobs)
        end
        if source_cache and source_cache ~= "" then
            table.insert(argv, "--source-dir=" .. modules.path.absolute(source_cache))
        end
        if build_cache and build_cache ~= "" then
            table.insert(argv, "--build-dir=" .. modules.path.absolute(build_cache))
        end
        -- Custom task options cannot be combined reliably with xmake's global
        -- -P option. Running in the tagged source root avoids that ambiguity.
        local envs = modules.meson.buildenvs(package, {
            packagedeps = {"glib", "pixman", "libsdl2"}
        })
        modules.os.vrunv(modules.os.programfile(), argv, {curdir = root, envs = envs})
        check(modules.os.isfile(modules.path.join(package:installdir(), "bin", triple .. "-gcc")), fail,
            "package(%s): SysToolchain source build did not install %s-gcc", package:name(), triple)
        check(modules.os.isfile(modules.path.join(package:installdir(), "bin", qemu_systems[triple])), fail,
            "package(%s): SysToolchain source build did not install %s", package:name(), qemu_systems[triple])
    end

    on_load(function (package)
        local triple, arch = target_triple(package)
        assert(triple,
            "package(%s): unsupported target architecture '%s'; expected %s",
            package:name(), arch ~= "" and arch or "<unset>", supported_arches_message())
        assert(package:config("host_platform") == os.host() and
               package:config("host_arch") == os.arch(),
            "package(%s): cached host identity does not match this process", package:name())
        package:addenv("PATH", "bin")
        if package:config("build_from_source") then
            package:add("deps", "make", {host = true, kind = "binary"})
            package:add("deps", "m4", {host = true, kind = "binary"})
            package:add("deps", "ninja", {host = true, kind = "binary"})
            package:add("deps", "pkg-config", {host = true, kind = "binary"})
            package:add("deps", "python 3.x", {host = true, kind = "binary"})
            package:add("deps", "glib", {host = true, configs = {shared = false}})
            package:add("deps", "pixman", {host = true, configs = {shared = false}})
            local sdl_configs = {
                shared = false,
                sdlmain = false
            }
            if os.host() == "linux" then
                sdl_configs.x11 = true
                sdl_configs.wayland = false
            end
            package:add("deps", "libsdl2", {host = true, configs = sdl_configs})
        end
    end)

    on_install("@linux", "@macosx", function (package)
        local triple, arch = target_triple(package)
        assert(triple,
            "package(%s): unsupported target architecture '%s'; expected %s",
            package:name(), arch ~= "" and arch or "<unset>", supported_arches_message())
        local runtime = {os = os, path = path, io = io}
        if package:config("build_from_source") then
            runtime.meson = import("package.tools.meson")
            install_from_source(package, triple, arch, runtime, raise)
        else
            runtime.http = import("net.http")
            runtime.hash = hash
            runtime.archive = import("utils.archive")
            install_release(package, triple, runtime, raise)
        end
    end)

    on_test(function (package)
        local triple, arch = target_triple(package)
        assert(triple,
            "package(%s): unsupported target architecture '%s'", package:name(), arch)
        local installdir = package:installdir()
        local bindir = package:installdir("bin")
        local manifest = path.join(installdir, "share", "systoolchain", "manifest.txt")
        assert(os.isfile(manifest), "package(%s): SysToolchain manifest is missing", package:name())
        local metadata = {}
        for line in io.readfile(manifest):gmatch("[^\r\n]+") do
            local key, value = line:match("^([^=]+)=(.*)$")
            assert(key, "package(%s): malformed SysToolchain manifest line: %s", package:name(), line)
            metadata[key] = value
        end
        local expected_host = os.host() == "macosx" and "macos" or os.host()
        local expected_metadata = {
            format = "1",
            systoolchain = "0.1.0",
            target_arch = target_arches[triple],
            target = triple,
            host = expected_host,
            host_arch = normalized_host_arch(os.arch()),
            gcc = "14.2.0",
            binutils = "2.42",
            qemu = "10.2.0",
            dtc = "1.6.1",
            qemu_target = qemu_targets[triple],
            qemu_system = qemu_systems[triple],
            languages = "c,c++",
            multilib = "false"
        }
        for key, expected in pairs(expected_metadata) do
            assert(metadata[key] == expected,
                "package(%s): manifest %s mismatch (expected %s, got %s)",
                package:name(), key, expected, metadata[key] or "<missing>")
        end

        local license_root = path.join(installdir, "share", "licenses", "systoolchain")
        local project_license = path.join(license_root, "SysToolchain-LICENSE")
        assert(os.isfile(project_license) and os.filesize(project_license) > 0,
            "package(%s): SysToolchain license is missing or empty", package:name())
        for _, component in ipairs({"gcc", "binutils", "gmp", "mpfr", "mpc", "isl", "dtc", "qemu"}) do
            local files = os.files(path.join(license_root, component, "*"))
            assert(#files > 0, "package(%s): license files are missing for %s", package:name(), component)
            for _, licensefile in ipairs(files) do
                assert(os.filesize(licensefile) > 0,
                    "package(%s): empty license file: %s", package:name(), licensefile)
            end
        end

        for _, entry in ipairs(os.filedirs(path.join(installdir, "**"))) do
            if os.islink(entry) then
                local link = os.readlink(entry)
                assert(not path.is_absolute(link),
                    "package(%s): absolute symlink makes the toolchain non-relocatable: %s -> %s",
                    package:name(), entry, link)
                local resolved = path.absolute(path.join(path.directory(entry), link))
                assert(os.exists(resolved),
                    "package(%s): dangling symlink in toolchain: %s -> %s", package:name(), entry, link)
            end
        end

        for _, tool in ipairs({
            "gcc", "g++", "as", "ld", "ar", "ranlib", "nm", "strip",
            "objcopy", "objdump", "readelf"
        }) do
            assert(os.isfile(path.join(bindir, triple .. "-" .. tool)),
                "package(%s): installed tool is missing: %s-%s", package:name(), triple, tool)
        end

        local gcc = path.join(bindir, triple .. "-gcc")
        local gxx = path.join(bindir, triple .. "-g++")
        assert(os.iorunv(gcc, {"-dumpmachine"}):trim() == triple,
            "package(%s): compiler target mismatch", package:name())
        assert(os.iorunv(gcc, {"-dumpfullversion"}):trim() == "14.2.0",
            "package(%s): expected GCC 14.2.0", package:name())
        local ld_version = os.iorunv(path.join(bindir, triple .. "-ld"), {"--version"})
        assert(ld_version:find("2.42", 1, true),
            "package(%s): expected Binutils 2.42", package:name())
        local libgcc = os.iorunv(gcc, {"-print-libgcc-file-name"}):trim()
        assert(os.isfile(libgcc) and os.filesize(libgcc) > 0,
            "package(%s): libgcc is missing or empty: %s", package:name(), libgcc)
        local ar = path.join(bindir, triple .. "-ar")
        for _, name in ipairs({"libstdc++.a", "libsupc++.a"}) do
            local archivefile = os.iorunv(gxx, {"-print-file-name=" .. name}):trim()
            assert(archivefile ~= name and os.isfile(archivefile) and os.filesize(archivefile) > 0,
                "package(%s): G++ cannot locate a non-empty %s: %s", package:name(), name, archivefile)
            assert(os.iorunv(ar, {"t", archivefile}):trim() ~= "",
                "package(%s): C++ runtime archive has no readable members: %s", package:name(), archivefile)
        end

        local qemu = path.join(bindir, qemu_systems[triple])
        assert(os.isfile(qemu), "package(%s): installed QEMU is missing: %s", package:name(), qemu)
        local qemu_version = os.iorunv(qemu, {"--version"})
        assert(qemu_version:find("QEMU emulator version 10.2.0", 1, true),
            "package(%s): expected QEMU 10.2.0", package:name())
        assert(os.iorunv(qemu, {"-machine", "help"}):trim() ~= "",
            "package(%s): QEMU machine list is empty", package:name())
        local qemu_displays = os.iorunv(qemu, {"-display", "help"})
        assert(qemu_displays:find("none", 1, true) and qemu_displays:find("sdl", 1, true),
            "package(%s): QEMU must provide none and sdl display backends", package:name())
        local qemu_share = path.join(installdir, "share", "qemu")
        assert(os.isdir(qemu_share) and #os.files(path.join(qemu_share, "**")) > 0,
            "package(%s): QEMU firmware/data directory is missing or empty", package:name())

        local workdir = os.tmpfile() .. ".systoolchain"
        os.mkdir(workdir)
        local csource = path.join(workdir, "start.c")
        local cxxsource = path.join(workdir, "smoke.cpp")
        local cobject = path.join(workdir, "start.o")
        local cxxobject = path.join(workdir, "smoke.o")
        local executable = path.join(workdir, "smoke.elf")
        local binary = path.join(workdir, "smoke.bin")
        io.writefile(csource, "void _start(void) { for (;;) {} }\n")
        io.writefile(cxxsource, [[
#include <cstdint>
extern "C" std::uint32_t systoolchain_smoke() { return UINT32_C(0x5a5a5a5a); }
]])
        os.vrunv(gcc, {"-ffreestanding", "-fno-stack-protector", "-c", csource, "-o", cobject})
        os.vrunv(gxx, {"-ffreestanding", "-fno-exceptions", "-fno-rtti", "-c", cxxsource, "-o", cxxobject})
        os.vrunv(gcc, {"-nostdlib", "-static", "-Wl,-e,_start", cobject, cxxobject, "-o", executable})
        os.vrunv(path.join(bindir, triple .. "-objdump"), {"-f", executable})
        os.vrunv(path.join(bindir, triple .. "-objcopy"), {"-O", "binary", executable, binary})
        assert(os.isfile(binary) and os.filesize(binary) > 0,
            "package(%s): objcopy did not produce a non-empty binary", package:name())
        os.tryrm(workdir)
    end)
