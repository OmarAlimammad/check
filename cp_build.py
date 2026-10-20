"""cp_build - the logic behind the `build` and `run` commands.

`build [-d] [--print-path] <source...>` compiles to .cache/<name>, skipping
sources that are already current. `run [-] [-d] <source...>` builds, then
replaces itself with the binary. `check` uses both, and `build --print-path`
to find the binary it plants in each sample's temp dir.

`run` is started once per sample, so the path that finds the binary current
and execs it imports nothing beyond os/sys: Python's startup is already most
of its overhead, and subprocess alone would nearly double it.
"""

from __future__ import annotations

import os
import sys

DEBUG_FLAGS = ["-g", "-fsanitize=address,undefined"]


def err(msg: str) -> None:
    print(msg, file=sys.stderr)


def _stem(path: str) -> str:
    name = os.path.basename(path)
    return name[:name.rindex(".")] if "." in name else name


def bin_path(args: list[str], debug: bool) -> str:
    """The cached binary for a build: .cache/<source filename minus extension>.

    One binary per source. Everything used to compile to a single ./bin, so a
    timestamp check could not tell the binary came from a *different* source:
    after building a.cpp, an older b.cpp still looked up to date and `run b.cpp`
    silently ran A's program. Keying on the source name fixes that, and
    switching between problems no longer recompiles.

    Several sources compiled together (`build grader.cpp sol.cpp`) get their
    stems joined with '+', .cache/grader+sol, so they never share a binary with
    a build of any one of them. Extra compiler flags (`build a.cpp -lm`) are not
    sources: only arguments naming existing files count, beyond the first.
    """
    sources = [args[0]] + [a for a in args[1:]
                           if not a.startswith("-") and os.path.isfile(a)]
    name = "+".join(_stem(s) for s in sources)
    return os.path.join(".cache", name + (".dbg" if debug else ""))


def _mtime(path: str) -> int | None:
    try:
        return os.stat(path).st_mtime_ns
    except OSError:
        return None


def _is_current(binary: str, stamp: str, key: str, args: list[str]) -> bool:
    built = _mtime(binary)
    if built is None:
        return False
    try:
        with open(stamp) as f:
            if f.read().rstrip("\n") != key:
                return False                 # compiler or flags changed
    except OSError:
        return False
    # Arguments that aren't files (extra compiler flags) never count as newer.
    return not any((_mtime(a) or 0) > built for a in args)


def build(args: list[str], debug: bool) -> int:
    """Compile `args` (its sources name the binary) unless already current.

    `args` goes to the compiler verbatim, so `build a.cpp -lm` works; it is also
    part of the stamp, as are $CXX and the flags, so changing any of them
    rebuilds.
    """
    cxx = os.environ.get("CXX") or "c++"
    flags = DEBUG_FLAGS if debug else []
    binary = bin_path(args, debug)
    stamp = binary + ".flags"
    key = f"{cxx} {' '.join(flags)} -- {' '.join(args)}"

    if _is_current(binary, stamp, key, args):
        return 0

    try:
        os.makedirs(os.path.dirname(binary), exist_ok=True)
        # Drop the stamp first so a failed compile can never leave a binary
        # that claims to be current.
        if os.path.lexists(stamp):
            os.remove(stamp)
    except OSError as e:
        err(f"build: {e}")
        return 1

    import subprocess                        # only paid for when compiling
    # Split like the shell would: CXX="ccache clang++" is two words.
    cmd = cxx.split() + flags + ["-o", binary] + args
    try:
        rc = subprocess.run(cmd).returncode
    except FileNotFoundError:
        err(f"build: {cmd[0]}: command not found")
        return 127
    if rc != 0:
        return 128 - rc if rc < 0 else rc    # signal death: 128+N, like a shell

    with open(stamp, "w") as f:
        f.write(key + "\n")
    return 0


def build_main(argv: list[str]) -> int:
    debug = print_path = False
    while argv:
        if argv[0] in ("-d", "--debug"):
            debug = True
        elif argv[0] == "--print-path":
            print_path = True
        elif argv[0] == "--":
            argv = argv[1:]
            break
        else:
            break
        argv = argv[1:]
    if not argv:
        err("build: usage: build [-d] [--print-path] <source...>")
        return 2

    if print_path:
        print(bin_path(argv, debug))
        return 0
    try:
        return build(argv, debug)
    except KeyboardInterrupt:
        return 130


def run_main(argv: list[str]) -> int:
    """run [-] [-d] <source...>

      -    read stdin from ./input instead of the terminal
      -d   build with sanitizers
    """
    debug = False
    infile = None
    while argv:
        arg = argv[0]
        if arg == "-":
            infile = "input"
        elif arg in ("-d", "--debug"):
            debug = True
        elif arg == "--":
            argv = argv[1:]
            break
        elif arg.startswith("-"):
            err(f"run: unknown option: {arg}")
            return 2
        else:
            break
        argv = argv[1:]
    if not argv:
        err("run: usage: run [-] [-d] <source...>")
        return 2

    try:
        rc = build(argv, debug)
    except KeyboardInterrupt:
        return 130
    if rc != 0:
        return rc

    if infile is not None:
        try:
            fd = os.open(infile, os.O_RDONLY)
        except OSError:
            err(f"run: no such input file: {infile}")
            return 2
        os.dup2(fd, 0)
        os.close(fd)

    # exec rather than spawn: the solution takes over this process, so its exit
    # status and signals reach the caller untouched and nothing lingers around it.
    binary = bin_path(argv, debug)
    try:
        os.execv(binary, [binary])
    except OSError as e:
        err(f"run: {binary}: {e.strerror}")
        return 126
