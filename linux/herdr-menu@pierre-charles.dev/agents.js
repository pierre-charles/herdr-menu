// The agent logic shared by the panel button, with no GNOME imports so `node linux/test.mjs` can check it.
// It mirrors the Mac island's Model (IslandModel.swift): same states, same order, same ✓ rules.

// Most urgent first: blocked, error, finished and unseen, working, then the rest
export function rank(item, unseen) {
    if (item.state === 'done' && unseen.has(item.block)) return 2;
    return {blocked: 0, error: 1, working: 3, done: 4}[item.state] ?? 5;
}

// herdr's agents from `herdr api snapshot`, with their workspace as the session, like the Mac's setHerdr
export function herdrItems(snap) {
    const names = new Map((snap?.workspaces ?? []).map(w => [w.workspace_id, w.label]));
    return (snap?.agents ?? []).map(a => ({
        session: a.workspace_id,
        label: names.get(a.workspace_id) || a.terminal_title_stripped || a.agent || 'pane',
        block: a.pane_id,
        state: !a.agent_status || a.agent_status === 'unknown' ? 'idle' : a.agent_status,
        app: a.agent,
        herdr: true,
    }));
}

// A herdr TUI client is `herdr [--options]` or `herdr session attach <name>`, not the server or a one-shot call
export function isHerdrClient(args) {
    const [exe, a1, a2] = args;
    if (exe !== 'herdr' && !exe?.endsWith('/herdr')) return false;
    return args.length === 1 || (a1.startsWith('-') && a1 !== '--machine') || (a1 === 'session' && a2 === 'attach');
}

export class Agents {
    items = [];
    unseen = new Set(); // blocks that finished while you weren't looking at them
    #last = new Map(); // block -> state at the last update

    // looking(item): its session is on screen, so a finish there doesn't count as unseen
    update(items, looking) {
        for (const i of items) {
            const old = this.#last.get(i.block);
            if (old !== undefined && old !== i.state && i.state === 'done' && !looking(i)) this.unseen.add(i.block);
            if (i.state !== 'done') this.unseen.delete(i.block);
        }
        const present = new Set(items.map(i => i.block));
        for (const b of this.unseen) if (!present.has(b)) this.unseen.delete(b); // a closed pane can't be looked at
        this.#last = new Map(items.map(i => [i.block, i.state]));
        this.items = items;
    }

    seen(blocks) {
        for (const b of blocks) this.unseen.delete(b);
    }

    get sorted() {
        return [...this.items].sort((a, b) => rank(a, this.unseen) - rank(b, this.unseen) || a.label.localeCompare(b.label));
    }

    // What the panel shows, most urgent first: ✋ blocked, ✓ finished and unseen, ✦ working
    get summary() {
        const blocked = this.items.filter(i => i.state === 'blocked').length;
        const working = this.items.filter(i => i.state === 'working').length;
        return [['✋', blocked], ['✓', this.unseen.size], ['✦', working]]
            .filter(([, n]) => n > 0).map(([s, n]) => `${s} ${n}`).join('  ');
    }
}
