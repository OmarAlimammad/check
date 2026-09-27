# cp.sh - the `build` and `run` helpers that `check` compiles and runs with.
#
# Plain POSIX sh, so it can be sourced from bash, zsh, dash, ...:
#
#   . /path/to/cp.sh
#
# `check` sources it on its own, so that is only needed to use `build`/`run`
# by hand. The compiler is $CXX, default `c++`.
#
# Each function starts by switching zsh into sh emulation for its own duration,
# so the code below behaves the same there (word splitting of $flags, mainly).

# Binary for a source file: $1 = mode (opt|dbg), $2 = first source.
_cp_binpath() {
  [ -n "${ZSH_VERSION-}" ] && emulate -L sh
  local b
  b=${2##*/}
  b=".cache/${b%.*}"
  [ "$1" = dbg ] && b="$b.dbg"
  printf '%s\n' "$b"
}

# build [-d] <source...>
#
# One cached binary per source. Everything used to compile to a single ./bin,
# so a timestamp check could not tell the binary came from a *different*
# source: after building a.cpp, an older b.cpp still looked up to date and
# `run b.cpp` silently ran A's program. Keying on the source name fixes that,
# and switching between problems no longer recompiles.
build() {
  [ -n "${ZSH_VERSION-}" ] && emulate -L sh
  local mode cxx flags bin stamp key rebuild src
  mode=opt
  case ${1-} in
    (-d|--debug) mode=dbg; shift ;;
  esac
  [ $# -gt 0 ] || { printf '%s\n' "build: usage: build [-d] <source...>" >&2; return 2; }

  cxx=${CXX:-c++}
  flags=
  [ "$mode" = dbg ] && flags="-g -fsanitize=address,undefined"

  bin=$(_cp_binpath "$mode" "$1")
  stamp="$bin.flags"
  key="$cxx $flags -- $*"

  mkdir -p "${bin%/*}" || return

  rebuild=0
  [ -f "$bin" ] || rebuild=1
  { [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$key" ]; } || rebuild=1   # flags changed
  for src in "$@"; do
    [ "$src" -nt "$bin" ] && { rebuild=1; break; }
  done
  [ "$rebuild" = 1 ] || return 0

  # Drop the stamp first so a failed compile can never leave a binary that
  # claims to be current.
  rm -f "$stamp"
  # Unquoted on purpose: CXX="ccache clang++" and the flags must split.
  $cxx $flags -o "$bin" "$@" || return
  printf '%s\n' "$key" > "$stamp"
}

# run [-] [-d] <source...>
#   -    read stdin from ./input instead of the terminal
#   -d   build with sanitizers
run() {
  [ -n "${ZSH_VERSION-}" ] && emulate -L sh
  local mode infile bin
  mode=opt
  infile=

  while [ $# -gt 0 ]; do
    case $1 in
      (-)          infile=input; shift ;;
      (-d|--debug) mode=dbg;     shift ;;
      (--)         shift; break ;;
      (-*)         printf '%s\n' "run: unknown option: $1" >&2; return 2 ;;
      (*)          break ;;
    esac
  done
  [ $# -gt 0 ] || { printf '%s\n' "run: usage: run [-] [-d] <source...>" >&2; return 2; }

  if [ "$mode" = dbg ]; then
    build -d "$@" || return
  else
    build "$@" || return
  fi

  bin=$(_cp_binpath "$mode" "$1")
  if [ -n "$infile" ]; then
    [ -r "$infile" ] || { printf '%s\n' "run: no such input file: $infile" >&2; return 2; }
    "$bin" < "$infile"
  else
    "$bin"
  fi
}
