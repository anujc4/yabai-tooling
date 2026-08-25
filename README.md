# yabai-stacks

Stack indicators for [yabai](https://github.com/koekeishiya/yabai). Stacked
windows get a strip of app icons showing every window in the stack, with the
focused one highlighted. Click an icon to focus that window.

Runs as a background process launched from `yabairc`, like `borders`. Swift, no
dependencies.

## Install

```sh
brew tap anujc4/yabai-tooling https://github.com/anujc4/yabai-tooling
brew install yabai-stacks
```

Builds from source, so a Swift 6 toolchain is needed — Xcode or
`xcode-select --install`.

## Use

One line in `~/.config/yabai/yabairc`:

```sh
yabai-stacks --icon-size 32 --position right &
```

It registers and removes its own yabai signals; no signal config needed.

## Options

| Flag | Default | |
| --- | --- | --- |
| `--icon-size <pt>` | `28` | Icon edge length |
| `--icon-spacing <pt>` | `4` | Gap between icons |
| `--padding <pt>` | `5` | Inset from the strip edge |
| `--corner-radius <pt>` | `6` | Rounds the strip and the active ring |
| `--active-color <color>` | `0xffd65d0e` | Ring around the focused icon |
| `--background-color <color>` | `0x801d2021` | Strip background |
| `--inactive-opacity <0..1>` | `0.45` | Opacity of unfocused icons |
| `--border-width <pt>` | `0` | Thickness of the active ring |
| `--position auto\|left\|right` | `auto` | Which corner. `auto` follows the window's half of the screen |
| `--orientation horizontal\|vertical` | `vertical` | Which way icons run |
| `--titlebar-inset <pt>` | `78` | Clearance for the window controls, left anchor only |
| `--offset-x`, `--offset-y` | `0` | Nudge from the anchored corner |
| `--min-stack-size <n>` | `2` | Smallest stack that gets a strip |
| `--hide-on-hover` | off | Hide while the cursor is over it; icons stop being clickable |
| `--help`, `--version` | | |

Colors take `0xAARRGGBB`, `0xRRGGBB` or `#RRGGBB`.

## Notes

**Your layout is never modified.** The only commands sent to yabai are
read-only queries, `window --focus <id>`, and `signal --add`/`--remove` on its
own `yabai-stacks.` labels. `YabaiCommand.argv` is internal, so spelling
anything else is a compile error.

**Your own yabai signals are safe.** Labels are derived from the event, so the
program cannot name — and cannot remove — a signal you defined.

**A stack with no highlight is correct.** At most one window is focused
system-wide, so a stack on a visible but unfocused display has no highlight.

**Nothing polls.** It blocks until yabai fires a signal, and coalesces bursts
into one repaint.

## Develop

```sh
make build
make test
```

Use `make test`, never bare `swift test` — on a Command Line Tools-only
toolchain SwiftPM cannot import `Testing` into its generated runner, so
`swift test` exits 0 having run nothing.

Three targets: `YabaiStacksCore` (pure logic, no AppKit, all the tests),
`YabaiStacksUI` (NSPanel and drawing), `yabai-stacks` (wiring).

## License

MIT
