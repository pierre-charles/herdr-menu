// A top bar button listing your herdr and Rex agents, most urgent first; click one to jump to it.
// The GNOME side of HerdrMenu.app: Rex's agents come from status.lua, herdr's from `herdr api snapshot`.
import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import {Agents, herdrItems, isHerdrClient} from './agents.js';

const STATES = {blocked: 'Needs you', error: 'Error', working: 'Working', done: 'Done', idle: 'Idle'};

// rexShowScript in HerdrMenu.swift: show a session in the Rex app, with the agent's block focused
const REX_SHOW = `local a = rex.args
rex.session.attach{session_id = a.session}
rex.call("session.focus_block", {session_id = a.session, block_id = a.block})
rex.client.queue("session.select", {session_id = a.session})`;

// GNOME Shell doesn't get your shell's PATH, so also look where the install scripts put the CLIs
function findCLI(name) {
    return [GLib.find_program_in_path(name), `${GLib.get_home_dir()}/.local/bin/${name}`, `/usr/local/bin/${name}`]
        .find(p => p && GLib.file_test(p, GLib.FileTest.IS_EXECUTABLE)) ?? null;
}

// stdout, or null if it couldn't start or failed
function run(argv) {
    return new Promise(resolve => {
        try {
            const p = Gio.Subprocess.new(argv, Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
            p.communicate_utf8_async(null, null, (_p, res) => {
                try {
                    const [, out] = p.communicate_utf8_finish(res);
                    resolve(p.get_successful() ? out : null);
                } catch {
                    resolve(null);
                }
            });
        } catch {
            resolve(null);
        }
    });
}

// ponytail: guesses the Rex app's window by its WM class; match its real app id once Rex ships for Linux
const isRexWindow = w => /rex/i.test(w.get_wm_class() ?? '');

export default class HerdrMenuExtension extends Extension {
    enable() {
        this._agents = new Agents();
        this._rexItems = [];
        this._herdrItems = [];
        this._rexVisible = null; // the session the Rex app shows
        this._herdrShowing = null; // herdr's focused workspace
        this._terminalPids = new Set(); // the herdr client and its ancestors, one of which owns its terminal window
        this._rex = findCLI('rex');
        this._herdr = findCLI('herdr');

        this._button = new PanelMenu.Button(0.0, this.metadata.name);
        const box = new St.BoxLayout();
        box.add_child(new St.Icon({icon_name: 'utilities-terminal-symbolic', style_class: 'system-status-icon'}));
        this._label = new St.Label({y_align: Clutter.ActorAlign.CENTER, style: 'padding-left: 4px'});
        box.add_child(this._label);
        this._button.add_child(box);
        Main.panel.addToStatusArea(this.uuid, this._button);

        // Looking at a finished agent's session clears its ✓
        global.display.connectObject('notify::focus-window', () => this._refresh(), this);
        this._watchRex();
        this._poll = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            this._pollHerdr();
            return GLib.SOURCE_CONTINUE;
        });
        this._refresh();
    }

    disable() {
        global.display.disconnectObject(this);
        GLib.source_remove(this._poll);
        if (this._restart) GLib.source_remove(this._restart);
        const p = this._rexProc;
        this._rexProc = null; // before force_exit, so its wait callback doesn't restart it
        p?.force_exit();
        this._button.destroy();
        this._button = this._label = this._agents = this._shown = null;
    }

    // `rex do --all` keeps status.lua running, printing a JSON line at start and on every change
    _watchRex() {
        if (!this._rex) return;
        const script = new TextDecoder().decode(GLib.file_get_contents(`${this.path}/status.lua`)[1]);
        let p;
        try {
            // Without --autostart=false, restarting this every 2s would start the Rex server whenever it's down
            p = Gio.Subprocess.new([this._rex, '--autostart=false', 'do', '--all', '-e', script],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE);
        } catch {
            return;
        }
        this._rexProc = p;
        const lines = new Gio.DataInputStream({base_stream: p.get_stdout_pipe(), close_base_stream: true});
        const read = () => lines.read_line_async(GLib.PRIORITY_DEFAULT, null, (_s, res) => {
            let line = null;
            try {
                [line] = lines.read_line_finish_utf8(res);
            } catch {}
            if (line === null || this._rexProc !== p) return;
            try {
                const snap = JSON.parse(line);
                this._rexVisible = snap.visible ?? null;
                this._rexItems = snap.items.map(i => ({...i, label: i.label || i.app || 'session'}));
                this._refresh();
            } catch {}
            read();
        });
        read();
        // A Rex server restart ends the script, so start it again
        p.wait_async(null, () => {
            if (this._rexProc !== p) return;
            this._rexItems = [];
            this._refresh();
            this._restart = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
                this._restart = 0;
                this._watchRex();
                return GLib.SOURCE_REMOVE;
            });
        });
    }

    // Only while a herdr client runs, so polling never starts a herdr server
    async _pollHerdr() {
        if (!this._herdr) return;
        const ps = (await run(['ps', '-e', '-o', 'pid=,ppid=,args=']) ?? '').split('\n')
            .map(l => l.trim().split(/\s+/)).filter(t => t.length > 2);
        const parent = new Map(ps.map(([pid, ppid]) => [pid, ppid]));
        let pid = ps.find(t => isHerdrClient(t.slice(2)))?.[0];
        const snap = pid ? await run([this._herdr, 'api', 'snapshot']) : null;
        if (!this._button) return; // disabled while waiting
        this._terminalPids = new Set();
        for (; pid && pid !== '1'; pid = parent.get(pid)) this._terminalPids.add(Number(pid));
        let s = null;
        try {
            s = JSON.parse(snap).result.snapshot;
        } catch {}
        this._herdrShowing = s?.workspaces?.find(w => w.focused)?.workspace_id ?? null;
        this._herdrItems = herdrItems(s);
        this._refresh();
    }

    _isTerminal(w) {
        return this._terminalPids.has(w.get_pid());
    }

    // Its session is on screen and its window has focus, so you can already see it
    _looking(i) {
        const w = global.display.focus_window;
        if (!w) return false;
        return i.herdr ? i.session === this._herdrShowing && this._isTerminal(w) : i.session === this._rexVisible && isRexWindow(w);
    }

    _refresh() {
        const items = [...this._rexItems, ...this._herdrItems];
        this._agents.update(items, i => this._looking(i));
        this._agents.seen(items.filter(i => this._looking(i)).map(i => i.block));
        this._label.text = this._agents.summary;

        // Rebuilt only when it changes, or the herdr poll would redraw an open menu under the pointer every 2s
        const both = this._rexItems.length > 0 && this._herdrItems.length > 0;
        const key = JSON.stringify([both, [...this._agents.unseen], this._agents.sorted.map(i => [i.block, i.label, i.state])]);
        if (key === this._shown) return;
        this._shown = key;
        const menu = this._button.menu;
        menu.removeAll();
        for (const i of this._agents.sorted) {
            const unseen = this._agents.unseen.has(i.block);
            const row = new PopupMenu.PopupMenuItem(i.label);
            const state = unseen ? 'Finished' : STATES[i.state] ?? i.state;
            row.add_child(new St.Label({
                text: [state, both ? (i.herdr ? 'herdr' : 'Rex') : null].filter(Boolean).join(' · '),
                x_expand: true, x_align: Clutter.ActorAlign.END, style_class: 'popup-inactive-menu-item',
            }));
            if (i.state === 'blocked' || unseen) row.setOrnament(PopupMenu.Ornament.DOT);
            row.connect('activate', () => this._jump(i));
            menu.addMenuItem(row);
        }
        if (items.length === 0) menu.addMenuItem(new PopupMenu.PopupMenuItem('No agents', {reactive: false}));
    }

    async _jump(i) {
        this._agents.seen([i.block]);
        const ok = i.herdr
            ? await run([this._herdr, 'agent', 'focus', i.block])
            : await run([this._rex, 'do', '-e', REX_SHOW, `session=${i.session}`, `block=${i.block}`]);
        if (ok === null || !this._button) return;
        const w = global.get_window_actors().map(a => a.meta_window).find(w => i.herdr ? this._isTerminal(w) : isRexWindow(w));
        if (w) Main.activateWindow(w);
        this._refresh();
    }
}
