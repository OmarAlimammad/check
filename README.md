# check

> Built around one person's Hyprland + zsh + clang setup. The shell helpers
> are plain POSIX `sh` and work from bash or zsh, but on Ubuntu/macOS you will
> likely need to adapt the autostart step (a `systemd --user` service or
> launchd instead of Hyprland's `exec-once`), see
> [Competitive Companion setup](#competitive-companion-setup).

Runs a problem's sample tests against a solution. The samples come from the
[Competitive Companion](https://github.com/jmerle/competitive-companion)
browser extension: click it on a problem page and it sends the problem to
`check listen`, a small local listener that caches it. Then:

```
check a.cpp
```

`check` itself only reads that cache. It makes no network connections and
never talks to the browser, so it works on pages behind your login and never
trips rate limiting.

It works on **every judge Competitive Companion supports**: Codeforces,
AtCoder, CSES, Kattis, HackerRank and 100+ others. Problem selection goes by
the problem's name, so nothing depends on Codeforces URL patterns.

Compiling and running are **not** reimplemented; `check` shells out to the
`run - <file>` helper from [`cp.sh`](#the-cpsh-helpers) for every sample and
only handles picking the problem, feeding the samples in, and diffing.

## Install

```
git clone https://github.com/USER/check.git
cd check
./install.sh
```

- **Requirements:** Python 3 (standard library only, so `requirements.txt`
  is intentionally empty and there is nothing to `pip install`), a POSIX
  `sh`, and a C++ compiler. `cp.sh` compiles with `$CXX`, default `c++`.
- **`install.sh`** symlinks `check` into `~/.local/bin` (or into `$PREFIX` if
  set: `PREFIX=/usr/local/bin ./install.sh`) and prints the remaining steps.
  To do it by hand: `ln -s "$PWD/check" ~/.local/bin/check`. Make sure that
  directory is on your `PATH`.
- **`cp.sh`** is found automatically: `check` follows its own symlink back to
  the checkout and sources the `cp.sh` next to it. Set `$CHECK_CP_SH` to use a
  different file. You only need to source it yourself to use `build`/`run` by
  hand. Add this to `~/.bashrc` or `~/.zshrc`:

  ```
  . /path/to/check/cp.sh
  ```

- Then install the browser extension and start the listener, see below.

## Competitive Companion setup

Install the extension:

- Chrome / Brave:
  <https://chromewebstore.google.com/detail/competitive-companion/cjnmckjndlpiamhfimnnjmnckgghkjbl>
- Firefox: <https://addons.mozilla.org/en-US/firefox/addon/competitive-companion/>

It sends problems to port **10042** by default, which is also `check listen`'s
default, so there is nothing to configure in the extension.

Start the listener:

```
check listen
```

It runs in the foreground and prints one line per problem it caches:

```
[companion] cached: G. Castle Defense (GCastleDefense)
```

To keep it running permanently under Hyprland, start it from
`~/.config/hypr/hyprland.conf`:

```
exec-once = check listen
```

or from a keybind:

```
bind = SUPER, C, exec, check listen
```

or as a systemd user service, e.g. `~/.config/systemd/user/check-listen.service`:

```
[Unit]
Description=Competitive Companion listener for check

[Service]
ExecStart=%h/.local/bin/check listen

[Install]
WantedBy=default.target
```

then `systemctl --user enable --now check-listen`, and read its output with
`journalctl --user -u check-listen -f`.

To use another port, pass `check listen --port N` (or set
`$CHECK_COMPANION_PORT`) and change the port in the extension's settings to match.
A second `check listen` on a port already in use exits with an error rather
than running twice.

> **Note:** the listener binds `0.0.0.0`, so other machines on your network
> can reach it too. It only accepts well-formed problem JSON, and all a POST
> can do is add a cached problem, but on an untrusted network, firewall the
> port.

Verify it is live by sending it a problem by hand:

```
curl -X POST localhost:10042/ -d '{"name":"A. Test","tests":[{"input":"1\n","output":"1\n"}],"timeLimit":1000,"languages":{"java":{"taskClass":"ATest"}}}'
```

### What the listener does

- It takes `POST /` only, and answers anything else with 404 or 405. A body
  without `name`, `tests`, `timeLimit` and `languages.java.taskClass` is
  logged and gets a 400. The daemon keeps running.
- On a contest's all-problems page the extension sends one POST per problem,
  all sharing a `batch.id`. Nothing from the batch is written until all
  `batch.size` problems have arrived, and then each is written to its own
  file. If a batch is still incomplete after 60s, whatever did arrive is
  cached, so a lost request doesn't lose the rest.
- Each problem is saved to `~/.cache/check/companion/<taskClass>.json` (under
  `$XDG_CACHE_HOME` if set) as the full payload plus a `received_at`
  timestamp. `taskClass` is the extension's own filename-safe name for the
  problem.
- `~/.cache/check/companion/.last` names the most recently completed problem.
  For a batch, that is the last one received.
- Every write deletes cached problems older than 24 hours.

## Usage

```
check <source> [--problem STRING] [--timeout SECONDS] [--jobs N]
               [--verbose] [--silent]
check <source> --raw [--silent]
check listen [--port N]
```

| flag | meaning |
| --- | --- |
| `--problem STRING` | pick a cached problem by name instead of the most recent one, see below |
| `--timeout` | per-sample limit in seconds (default: the problem's own limit) |
| `-j`, `--jobs` | samples to run at once (default: one per CPU, capped at the sample count) |
| `-v`, `--verbose` | also print the problem's name, URL and group |
| `-s`, `--silent` | don't print the solution's stderr (still captured separately, never diffed) |
| `-r`, `--raw` | skip the samples and run the solution once, interactively. See [Raw mode](#raw-mode) |
| `--port N` | `check listen` only: port to listen on (default `10042`, or `$CHECK_COMPANION_PORT`) |

### Which problem it uses

By default, **whichever problem you clicked Competitive Companion on last**
(the one named in `.last`). If nothing has been received yet, or it was
pruned, `check` stops with:

```
check: no problem received yet — open the problem, click Competitive Companion, and make sure `check listen` is running
```

and exits `2`. It never guesses.

`--problem STRING` picks among everything cached instead. It is matched
case-insensitively against each problem's **name**:

```
check g.cpp --problem castle      # G. Castle Defense
```

- If one problem matches, that one is used.
- If several match, they are listed (name and taskClass) and you are asked to
  be more specific.
- If none match, the cached problems are listed.

The filename also helps, on judges whose names start with a letter
(`F2. Title` on Codeforces, `A - Title` on AtCoder). If the source is named
like a problem letter (`a.cpp`, `f2.cpp`), a problem named after that letter
counts as a match too. That settles a tie: `check a.cpp --problem sum` takes
`A. Sum` over `C. Another Sum`. It also acts as a fallback when no name
contains the string, with a warning saying so. After clicking on a contest's
all-problems page, `check f2.cpp --problem ''` therefore picks F2.

### Time limit

The per-sample timeout is the problem's own `timeLimit` from the payload
(sent in milliseconds, so 1500 is 1.5s). `--timeout` overrides it. If the
problem states no limit, 10s is used. The limit in force is printed before
the samples run.

It is a wall-clock limit, and samples run at the same time on shared cores, so a
solution genuinely close to the limit can measure slower than it would alone.
`--jobs 1` gives it the machine to itself.

`build` compiles without `-O2` (see [the `cp.sh` helpers](#the-cpsh-helpers)),
so local timings can run slower than the judge's optimised build.

### Output

One line goes out before the samples run: the problem's name, how many
samples, and the time limit in force:

```
G. Castle Defense, 3 samples, 1.5s limit
```

The limit is annotated when it did not come from the problem, e.g.
`5s limit (--timeout)`.

Each sample reports PASS/FAIL and the time it took. Failures show a line-by-line
diff (expected vs actual, trailing whitespace ignored). **stderr is captured
separately and printed under every sample**, pass or fail, so debug macros stay
visible instead of being mistaken for wrong output. `-s` drops it; it is still
kept out of the stdout being compared.

Samples are always printed in order — 1, 2, 3 — no matter which finished first,
so the output reads the same as if they had run one at a time.

Exit status: `0` all passed · `1` a sample failed or timed out · `2` compile
error, no problem received, `--problem` didn't pick exactly one, or the
problem is interactive.

#### Interactive problems

`check` doesn't do interactive judging. For a problem Competitive Companion
marks `interactive`, diffing stdin/stdout samples would always fail, so
`check` refuses with:

```
check: B. Guess: interactive problem — comparing stdin/stdout samples doesn't apply, run manually with `check b.cpp -r`
```

and exits `2`.

#### Raw mode

`check a.cpp -r` is a plain interactive `run a.cpp`: no cached problem, no
samples, no header line, and `./input` is neither read nor written. The source
is built with `build` first (a compile error is reported as one and exits `2`), then the
binary runs once with the terminal's stdin, stdout and stderr — nothing is
piped, so output appears immediately and you can type in response. Ctrl-D is
only needed if the program reads until EOF. Pipes and redirects work too:

```
echo 5 | check a.cpp -r
check a.cpp -r < in.txt
```

The limit is **5 seconds of CPU time**, not wall-clock, so time spent waiting
for you to type does not count. A program that hits it prints
`TIMEOUT (5s CPU)` to stderr. stderr is shown as normal; `-s` sends it to
`/dev/null`. Ctrl-C kills the program. `--problem`, `--timeout` and `--jobs`
are ignored.

Exit status: the program's own exit code · `1` CPU limit hit · `2` compile
error · `130` Ctrl-C.

### Samples run in parallel

All the samples run at once, which turns a slow solution's `check` from the sum
of its samples into roughly its slowest one. On a 3-sample problem with a
solution taking ~0.8s per sample, a full run went from 3.0s to 1.4s.

Concurrency is capped at one job per CPU (never more than the sample count), and
`--jobs N` sets it by hand. `--jobs 1` restores the old one-at-a-time behaviour.

### Your `input` file is never touched

`run -` reads stdin from a file named `input` in the current directory, so
samples running side by side would overwrite each other's input mid-run.

Each sample therefore gets a private temp directory holding the source, its own
`input`, and the compiled binary, and `run` is invoked with that as its working
directory. Your own `./input` is left exactly as it was — `check` no longer
writes to it at all. The temp directories are removed on the way out, including
after a failure or a Ctrl-C, which also kills any sample still running.

## Requirements

Python 3 and its standard library, nothing else to install, plus a POSIX `sh`
and a C++ compiler. The Competitive Companion extension goes in the browser;
see [setup](#competitive-companion-setup).

`check` finds `run`/`build` by looking for them on `PATH` first, then falling
back to sourcing `cp.sh` in plain `sh`: `$CHECK_CP_SH` if set, otherwise the
`cp.sh` next to the real (symlink-resolved) `check` script.

## Note on `build`

`check` calls `build` once up front rather than letting the first sample's `run`
do it, so a compile error is reported as a compile error instead of a failed
diff, and compiler output never lands in a sample's captured stderr.

It does **not** force a rebuild. `build` caches one binary per source under
`.cache/`, so an unchanged solution is not recompiled — a second `check` of the
same file skips the compiler entirely.

That cache is keyed on a path relative to the *current* directory, so a sample
running in its own temp dir would find nothing there and rebuild — once per
sample, which is exactly the cost that running them in parallel is meant to
avoid. `check` copies the binary it just built (and its `.flags` stamp, without
which `build` assumes the flags changed) into each temp dir, so `build` finds it
current and the compiler runs once per `check` regardless of the sample count.
It asks `cp.sh` for that path via `_cp_binpath` rather than hardcoding
`.cache/`, and copies rather than symlinks so a rebuild, if one ever did happen,
could not have every sample writing the same file at once.

## The `cp.sh` helpers

`cp.sh` defines the shell side of this workflow. It is plain POSIX `sh`, so
it can be sourced from bash, zsh or dash.

| command | what it does |
| --- | --- |
| `build [-d] <src...>` | compile to `.cache/<name>`, skipping unchanged sources |
| `run [-] [-d] <src...>` | build, then run — `-` reads stdin from `./input` |
| `run -d <src>` | build with `-fsanitize=address,undefined` and no optimisation |

Compiles with bare `$CXX` (default `c++`; e.g. `export CXX=clang++`) — no
`-std`, no `-O2` — which is the fastest setting and keeps a cold build at
~1.4s. `run -d` adds `-g -fsanitize=address,undefined`. Changing `$CXX`
triggers a rebuild, just like changing flags.

Add `.cache/` to your global gitignore.

**Why one binary per source.** Everything used to compile to a single `./bin`,
so a timestamp check couldn't tell the binary came from a *different* source:
after building `a.cpp`, an older `b.cpp` still looked up to date and `run b.cpp`
silently ran A's program. Keying the cache on the source name makes that
impossible, and switching between problems no longer recompiles.

**Compile times** measured on the author's machine, same file:

| flags | time |
| --- | --- |
| none (default c++17) | 1.4s |
| `-O2` | 1.9s |
| `-std=c++20 -O2` | 2.6s |
| `-std=c++23 -O2` | 4.8s |

Header parsing dominates — linking is free and `-O1` vs `-O2` barely differs.
A solution including `<bits/stdc++.h>` costs ~4.4s regardless; a precompiled
header brings that to ~1.7s if you ever need it.
