<p align="center">
  <img src="logo.png" width="128" alt="herdr's sheep logo">
</p>

<h1 align="center">HerdrMenu</h1>

<p align="center">A Rectangle-style macOS menu bar app for <a href="https://herdr.dev">herdr</a>.</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="https://herdr.dev"><img src="https://img.shields.io/badge/herdr-0.9.1%2B-94e2d5" alt="herdr 0.9.1+"></a>
</p>

<p align="center">
  <img src="screenshots/menu.png" width="396" alt="The HerdrMenu menu: agents with status dots, then Workspace, Tab and Pane actions with their herdr keybinds">
</p>

- **Agents** at the top of the menu, with herdr's status dots. Click one to jump to it.
- **A badge on the sheep** when an agent needs you (see [the sheep](#the-sheep) below).
- **One-click actions** for panes (split, zoom, focus, resize, swap, close), tabs and workspaces (new, rename, close), plus a list of your workspaces to jump between.
  **New tab…** and **New workspace…** ask for a name first; hold **⌥ Option** for the quick versions, which create them straight away like herdr's keybinds.
- **herdr's keybind next to each action,** so the menu doubles as a cheat sheet.

It calls the `herdr` CLI rather than faking keystrokes, so it acts on whichever pane you're looking at and doesn't need Accessibility permission. After a click, it brings your terminal to the front. The icon only appears while herdr is open.

### The sheep

| Icon | What it means |
|:---:|---|
| <img src="screenshots/badge-none.png" width="44" alt="The plain sheep icon"> | herdr is open and no agent needs you |
| <img src="screenshots/badge-blocked.png" width="44" alt="The sheep with a red badge"> | An agent is blocked, waiting on you (for example, for an approval) |
| <img src="screenshots/badge-done.png" width="44" alt="The sheep with a teal badge"> | An agent has finished and you haven't looked at it yet |

Hover over the sheep to see how many agents are blocked or done. Viewing a finished agent in herdr clears its badge.

### Several machines

<p align="center">
  <img src="screenshots/machines.png" width="366" alt="The menu with agents on this Mac and on a saved machine, build-box, each under its own heading">
</p>

If you've saved SSH machines with `herdr machine add`, the sheep's badge counts agents on all of them. **Machines** chooses how the menu shows them:

- **All together** (default): each enabled machine's agents under their own heading, and every machine's workspaces. The Workspace, Tab and Pane actions act on the machine the herdr TUI is showing, or Local, named in their headers.
- **One at a time**: a **Machine** section at the top picks one machine, and the rest of the menu shows and acts on just that one.

Everything goes through `herdr --machine <id> ...`, so it needs herdr 0.9.5 or later on both ends. A machine that doesn't answer within 3 seconds shows as *Not reachable*.

Clicking a remote agent moves focus on that machine's server. You only see it if your TUI is showing that machine, because the CLI can't switch the TUI's machine for you.

### Settings

- **Show**: agents and workspaces (default), agents only, or workspaces only.
- **Actions**: turn the Workspace, Tab and Pane action sections on or off (all on by default). The workspace list from **Show** stays either way.
- **Machines**: all together or one at a time (only with saved SSH machines).

These are stored in the app's defaults, e.g. `defaults write dev.pierre-charles.herdr-menu show agents` or `defaults write dev.pierre-charles.herdr-menu actions.pane off`.

## Requirements

- macOS 14 or later
- The Xcode command line tools (`xcode-select --install`), for `swiftc`
- herdr 0.9.1 or later, installed in `~/.local/bin` (herdr's install script), `/opt/homebrew/bin` or `/usr/local/bin`. If you've updated herdr, make sure the running server is the new version too: `herdr status` should show `server_binary_stale: no`.

## Install

```sh
git clone https://github.com/pierre-charles/herdr-menu.git
cd herdr-menu
./build.sh
open ~/Applications/HerdrMenu.app
```

`build.sh` builds and signs the app into `~/Applications`. Then open herdr, click the sheep in the menu bar and tick **Launch at login** so it starts every time you log in. It's listed in System Settings → General → Login Items.

## Update

```sh
git pull
./build.sh
```

`build.sh` restarts the app if it's running, so the new version takes over straight away.

## Uninstall

Untick **Launch at login**, choose **Quit**, then delete `~/Applications/HerdrMenu.app`.

## Notes

- The keybinds shown are your own: the menu reads `~/.config/herdr/config.toml` each time it opens and resolves them the way herdr does (your `prefix` and `[keys]` entries win, and a default that shares a key with one of your bindings, including `[[keys.command]]` keys, is dropped). Bindings must be on one line, e.g. `new_tab = "prefix+t"` or `new_tab = ["prefix+t", "ctrl+alt+t"]`; the first one is shown.
- The screenshots were made with a demo mode (made-up workspaces and agents) that has since been removed. To retake them, restore it from commit `bb7e941`.
- Status colours are herdr's Catppuccin palette, its default theme.
- The app icon is herdr's logo (`logo.png`), and the menu bar icon is the same logo converted to a template image (`sheep.png`).

## Licence

HerdrMenu's code is released under the [MIT License](LICENSE).

HerdrMenu is an unofficial companion app and isn't affiliated with herdr. The sheep logo comes from [herdrdev/herdr](https://github.com/herdrdev/herdr) (`assets/logo.svg`), and `logo.png` and `sheep.png` stay under herdr's [Apache License 2.0](LICENSE-APACHE). It's used as the app icon and converted to a monochrome menu bar icon.
