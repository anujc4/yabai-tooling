# yabai-stacks

Stack indicators for [yabai](https://github.com/koekeishiya/yabai). When a space
contains stacked windows, a small strip of app icons appears at the corner of
the stack showing every window in it, with the focused one highlighted. Click
an icon to focus that window.

Runs as a background process launched from `yabairc`, the same way `borders`
does. Written in Swift with no dependencies.

## Requirements

- macOS 14 or later
- yabai (developed against v7.1.24)
- Swift 6 toolchain (Xcode or Command Line Tools)

## Install

```sh
git clone https://github.com/anujc4/yabai-tooling.git
cd yabai-tooling
make install            # builds release and installs to /usr/local/bin
```

Use `make install PREFIX=~/.local` to install elsewhere.

## Usage

Add one line to `~/.config/yabai/yabairc`, next to `borders`:

```sh
yabai-stacks --icon-size 32 --active-color 0xffd65d0e &
```

That is the whole setup. `yabai-stacks` registers the yabai signals it needs at
startup and removes them again when it exits — you do not add `signal --add`
lines yourself. If it is killed outright, the stale signals are replaced on the
next launch rather than accumulating.

### Options

| Flag | Default | Meaning |
| --- | --- | --- |
| `--icon-size <pt>` | `28` | Icon edge length |
| `--icon-spacing <pt>` | `4` | Gap between icons |
| `--padding <pt>` | `5` | Inset between icons and the strip edge |
| `--corner-radius <pt>` | `6` | Strip corner radius |
| `--active-color <color>` | `0xffd65d0e` | Ring drawn around the focused icon |
| `--background-color <color>` | `0x801d2021` | Strip background |
| `--inactive-opacity <0..1>` | `0.45` | Opacity of unfocused icons |
| `--border-width <pt>` | `0` | Thickness of the ring around the active icon |
| `--position auto\|left\|right` | `auto` | Which corner of the stack |
| `--orientation horizontal\|vertical` | `vertical` | Which way icons run |
| `--offset-x <pt>` | `0` | Nudge inwards from the anchored corner |
| `--offset-y <pt>` | `0` | Nudge downwards |
| `--min-stack-size <n>` | `2` | Smallest stack that gets a strip |
| `--titlebar-inset <pt>` | `78` | Clearance for the window controls, left anchor only |
| `--hide-on-hover` | off | Strip slides away under the cursor instead of taking clicks |
| `--help`, `--version` | | |

Colors accept `0xAARRGGBB`, `0xRRGGBB` and `#RRGGBB`.

`--position auto` puts the strip on the left unless the stack's centre is past
its display's centre, in which case it goes on the right.

## Behaviour worth knowing

**Your layout is never modified.** The only commands this program can send to
yabai are read-only queries, `window --focus <id>`, and `signal --add`/`--remove`
restricted to its own `yabai-stacks.` labels. None of those move a window. That
is not a convention — the IPC layer accepts a `YabaiCommand` value whose `argv`
is internal to the module, so no caller can spell an arbitrary command, and it
is a compile error to try.

**Your own yabai signals are safe.** `yabai-stacks` registers signals under the
`yabai-stacks.` label prefix. Labels are derived from the event rather than
accepted as arguments, so the program has no way to name — and therefore no way
to remove — a signal you defined yourself.

**A stack with no highlight is correct.** The focused window is the only one
yabai reports as focused, and there is at most one across the whole system. A
stack on a visible but unfocused display legitimately has no highlighted icon.

**Nothing polls.** The daemon blocks waiting for yabai to fire a signal.
Refreshes coalesce over 40ms, because one user action typically emits several
signals in a burst.

**Mission Control gets the screen to itself.** yabai emits
`mission_control_enter` and `mission_control_exit`, so the strips slide off
their display edge while it is open and slide back afterwards. No polling and no
private API is involved, and a refresh landing in the middle keeps them parked.

**`--hide-on-hover` trades the click for the view.** By default the strip stays
put and clicking an icon focuses that window. With `--hide-on-hover` the strip
slides away while the cursor is over it and returns when the cursor leaves —
and it registers no click action at all, so clicks go to the window underneath
exactly as if the strip were not there. The two behaviours are exclusive: the
strip cannot both get out of the cursor's way and be clickable.

Hover is decided from the cursor position against where the strip *belongs*,
not where it currently is; a strip that has moved out of the way is never under
the cursor, and testing its live frame would bring it straight back. Detection
uses a mouse-movement `NSEvent` monitor, which needs no Accessibility grant
(only keyboard monitoring does) and does nothing at all while the cursor is
still. It is installed only when the flag is set and a strip exists.

## Development

```sh
make build
make test
```

**Always use `make test`, never bare `swift test`.** On a Command Line
Tools-only toolchain, SwiftPM cannot import `Testing` into its synthesised test
runner and `swift test` exits 0 having executed nothing. `make test` passes the
right flags and fails loudly if zero tests run.

The package is three targets:

| Target | Contents |
| --- | --- |
| `YabaiStacksCore` | Models, IPC, stack detection, geometry, config, reconciliation. Pure — imports no AppKit. |
| `YabaiStacksUI` | `NSPanel`, `CALayer` drawing, icon cache. |
| `yabai-stacks` | Wiring and lifecycle. |

Core holds all the logic precisely so it can be tested without a window server;
`docs/SPEC.md` records the yabai behaviour this was built against, including
several facts that were established empirically rather than from documentation.

## License

MIT
