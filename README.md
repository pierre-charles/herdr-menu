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
  <img src="screenshots/menu.png" width="400" alt="The HerdrMenu menu: agents with status dots, then Switch workspace and the Workspace, Tab and Pane submenus, each named after the focused one">
</p>

- **Agents** at the top of the menu, with herdr's status dots. Click one to jump to it.
- **A badge on the sheep** when an agent needs you (see [the sheep](#the-sheep) below).
- **One-click actions** for panes (split, zoom, focus, resize, swap, close), tabs and workspaces (new, rename, close), each section in a submenu named after the focused one, plus **Switch workspace** to jump between your workspaces.
  **New tab…** and **New workspace…** ask for a name first; hold **⌥ Option** for the quick versions, which create them straight away like herdr's keybinds.
- **herdr's keybind next to each action,** so the menu doubles as a cheat sheet.
- **An island around your MacBook's notch** for your herdr, Rex and cmux agents: what each one is doing, a ping when one needs you, and permission and plan cards you can answer from the notch (see [the island](#the-island) below).

### Submenus

| Switch workspace | Workspace |
|:---:|:---:|
| <img src="screenshots/switch-workspace.png" width="199" alt="Switch workspace: every workspace with its status dot, a checkmark on the current one"> | <img src="screenshots/workspace.png" width="305" alt="Workspace: New workspace…, Rename workspace and Close workspace with their keybinds"> |
| **Tab** | **Pane** |
| <img src="screenshots/tab.png" width="302" alt="Tab: New tab…, Rename tab and Close tab with their keybinds"> | <img src="screenshots/pane.png" width="315" alt="Pane: Split right, Split down, Toggle zoom, the Focus, Resize and Swap submenus, and Close pane"> |

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
  <img src="screenshots/machines.png" width="400" alt="All together: agents on this Mac and on a saved machine, build-box, each under its own heading">
  <img src="screenshots/one-at-a-time.png" width="400" alt="One at a time: a Machine section at the top picks Local or build-box">
</p>

If you've saved SSH machines with `herdr machine add`, the sheep's badge counts agents on all of them. **Machines** chooses how the menu shows them:

- **All together** (default): each enabled machine's agents under their own heading, and every machine's workspaces. The Workspace, Tab and Pane actions act on the machine the herdr TUI is showing, or Local, named in their headers.
- **One at a time**: a **Machine** section at the top picks one machine, and the rest of the menu shows and acts on just that one.

Everything goes through `herdr --machine <id> ...`, so it needs herdr 0.9.5 or later on both ends. A machine that doesn't answer within 3 seconds shows as *Not reachable*.

Clicking a remote agent moves focus on that machine's server. You only see it if your TUI is showing that machine, because the CLI can't switch the TUI's machine for you.

### Rex

<p align="center">
  <img src="screenshots/rex.png" width="400" alt="The menu in Rex mode with both open: the herdr / Rex switch at the top, then agents with a checkmark on the one in the session Rex shows, Switch session, and the Session, Tab and Pane submenus named after that session">
</p>

The menu drives whichever of **herdr** and **[Rex](https://www.superlogical.com/rex)** is open. When both are, a switch at the top of the menu picks one. In Rex mode the menu bar shows Rex's mascot instead of the sheep, and the menu works the same way, in Rex's words:

- **Agents** are terminals whose program reports a status to Rex (OSC 7501, as Claude Code does), with the same dots and badge. Click one to show its session in the Rex app and focus it. Rex keeps an agent done until it works again, so the menu does what herdr does: an agent is done (teal) from when it finishes until you look at its session in the Rex app, then idle. Agents that finished before the menu started count as seen.
- **Workspaces are sessions**, tabs are tabs (Rex's windows), and panes are panes (Rex's blocks). Swap is **Move**, Rex's name for it.
- **Machines are hosts**: everything in `rex hosts` is listed, through `rex -S <host> ...`.
- The actions run the Rex app's own actions (`rex do pane.split.right` and so on), so they act on whatever has focus in Rex. Renaming uses the app's inline rename, and new tabs and sessions don't ask for a name.
- **The section rows name the session, tab and pane the Rex app is showing,** with a checkmark on that session and its agents, as in herdr mode. The Rex server doesn't report which session the app shows, so the menu works it out from the app resizing a session's terminals when it shows them. Until you switch sessions once after the menu starts, nothing is named.
- Keybinds shown are the ones in your `init.lua` (`rex keymap`). The app's built-in shortcuts aren't visible to the server, so they don't show.

The icon shows while a herdr client or the Rex app is open. The badge counts the agents of the one the menu drives. It needs the `rex` CLI that comes with Rex.

### cmux

**[cmux](https://cmux.com)**'s agents show in [the island](#the-island), alongside herdr's and Rex's. The menu doesn't drive cmux yet, so its icon only shows while herdr or Rex is open.

- **Agents** are cmux terminals whose program reports a status (OSC 7501, as Claude Code does), from `cmux events`. Each is named after its cmux workspace. Click one to switch cmux to that workspace and focus it.
- **The ✓** stays until cmux is in front showing that workspace.
- **Socket access:** by default cmux only lets processes started inside cmux use its socket, which shuts the island out. In cmux's Settings → Automation, set **Socket Control Mode** to **Automation mode**, which also accepts other apps running as you. Password mode works too once you've set a socket password there. Don't use **Full open access**: it lets any local process drive your terminals.
- **cmux's own alerts** (rings, badges, notifications) still go off, so you may see things twice. Turn some off in cmux's Settings if you want; the island leaves them alone.
- **Not yet:** the island's permission and plan cards, and what each agent is doing, don't work in cmux panes yet.

It finds cmux wherever the app is installed, and uses the `cmux` CLI inside it.

### The island

<p align="center">
  <img src="screenshots/island-collapsed.png" width="221" alt="The collapsed island around the notch: an orange hand on the left and the number 1 on the right">
</p>

<p align="center">
  <img src="screenshots/island-expanded.png" width="456" alt="The island expanded: a permission card for an edit to middleware.ts with a diff and Deny, Always allow and Allow buttons, then four agents with what each is doing">
</p>

While herdr, Rex or [cmux](https://cmux.com) is open, a black pill sits around your MacBook's notch, a bit like the iPhone's Dynamic Island. It shows the agents of all three, whichever one the menu drives:

- **The sides of the notch** show the most urgent thing: ✋ when an agent needs you, ✓ when one has finished and you haven't looked at it yet, a spinning ✦ while agents work. The number is how many. When nothing's happening, the pill hides behind the notch.
- **Hover** to see every agent: its workspace or session, what it's doing right now ("Editing api-reference.md", "Running terraform plan") and for how long. A finished one shows your last prompt. Click one to jump to it.
- **Permission requests drop down from the notch** with the command or diff: Deny, Allow, or Always allow when Claude offers a rule. The prompt in the terminal still works too, and whichever you answer first wins.
- **Plans** from plan mode show up with their Markdown, and Keep planning or Approve plan.
- **It pings you** with a drop-down and a sound when an agent gets blocked or finishes, except when you're already looking at it: Rex in front showing that session, or herdr's terminal in front on that workspace.
- **Colours** are Catppuccin Macchiato in dark mode and Latte in light mode, with the Catppuccin colour nearest your macOS accent colour. The pill itself stays black, so it blends with the notch.

| Plan review | Light mode |
|:---:|:---:|
| <img src="screenshots/island-plan.png" width="400" alt="A plan card: Split the API reference, with headings, bullets and Keep planning and Approve plan buttons"> | <img src="screenshots/island-light.png" width="330" alt="The expanded island in the Latte light theme with a blue Allow button"> |

The agents and their states come from herdr, and from Rex (Claude Code reports them there with OSC 7501). A Rex agent's ✓ stays until you look at its session, like herdr's own done. cmux's agents come from cmux, see [cmux](#cmux). For what each one is doing, and the permission and plan cards, install the Claude Code hooks with **Island › Install Claude Code hooks…**, then restart your Claude sessions. That adds three hooks to `~/.claude/settings.json` which run this app with `--hook`. If the menu isn't running, or a session isn't in a herdr or Rex pane, the hook exits straight away and Claude carries on as normal. On a screen without a notch, the island is a small pill at the top centre.

### Settings

<p align="center">
  <img src="screenshots/settings.png" width="249" alt="The Show submenu: Agents and workspaces, Agents only, Workspaces only">
</p>

- **herdr / Rex** at the top, while both are open: which one the menu drives (`defaults write dev.pierre-charles.herdr-menu backend rex`).
- **Show**: agents and workspaces (default), agents only, or workspaces only (listed in the menu itself rather than under **Switch workspace**).
- **Actions**: turn the Workspace, Tab and Pane submenus on or off (all on by default). **Switch workspace** stays either way.
- **Machines** (**Hosts** for Rex): all together or one at a time (only with saved SSH machines or Rex hosts).
- **Island**: show the island, its sounds, its height (the notch's, or down to where the menu bar ends), and install or remove the Claude Code hooks.

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

If you installed the Claude Code hooks, choose **Island › Remove Claude Code hooks** first. Then untick **Launch at login**, choose **Quit**, and delete `~/Applications/HerdrMenu.app`.

## Notes

- The keybinds shown are your own: the menu reads `~/.config/herdr/config.toml` each time it opens and resolves them the way herdr does (your `prefix` and `[keys]` entries win, and a default that shares a key with one of your bindings, including `[[keys.command]]` keys, is dropped). Bindings must be on one line, e.g. `new_tab = "prefix+t"` or `new_tab = ["prefix+t", "ctrl+alt+t"]`; the first one is shown.
- The screenshots show made-up workspaces and agents, from fake `herdr` and `rex` CLIs fed to a throwaway copy of the app, so no real names reach the repo.
- Status colours are herdr's Catppuccin palette, its default theme.
- The app icon is herdr's logo (`logo.png`), and the menu bar icon is the same logo converted to a template image (`sheep.png`). Rex's mascot isn't in the repo: the app makes it from the image in your installed Rex app.

## Licence

HerdrMenu's code is released under the [MIT License](LICENSE).

HerdrMenu is an unofficial companion app and isn't affiliated with herdr. The sheep logo comes from [herdrdev/herdr](https://github.com/herdrdev/herdr) (`assets/logo.svg`), and `logo.png` and `sheep.png` stay under herdr's [Apache License 2.0](LICENSE-APACHE). It's used as the app icon and converted to a monochrome menu bar icon.
