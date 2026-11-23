// node linux/test.mjs: checks the GNOME extension's agent logic, which needs no GNOME to run
import assert from 'node:assert/strict';
import {Agents, herdrItems, isHerdrClient} from './herdr-menu@pierre-charles.dev/agents.js';

const item = (block, state, label = block) => ({session: 's', label, block, state});
const notLooking = () => false;

// Finishing while you're not looking counts as unseen, until it works again or you look at it
const a = new Agents();
a.update([item('b1', 'working'), item('b2', 'done')], notLooking); // already done at start: counts as seen
a.update([item('b1', 'done'), item('b2', 'done')], notLooking);
assert.deepEqual([...a.unseen], ['b1']);
assert.equal(a.summary, '✓ 1');
a.seen(['b1']);
assert.equal(a.unseen.size, 0);

// Finishing while you're looking never counts
a.update([item('b1', 'working')], notLooking);
a.update([item('b1', 'done')], () => true);
assert.equal(a.unseen.size, 0);

// Closing the pane drops its ✓
a.update([item('b1', 'working')], notLooking);
a.update([item('b1', 'done')], notLooking);
a.update([], notLooking);
assert.equal(a.unseen.size, 0);

// Most urgent first: blocked, then finished and unseen, then working, then the rest
const b = new Agents();
b.update([item('w', 'working'), item('i', 'idle'), item('d', 'working'), item('x', 'blocked')], notLooking);
b.update([item('w', 'working'), item('i', 'idle'), item('d', 'done'), item('x', 'blocked')], notLooking);
assert.deepEqual(b.sorted.map(i => i.block), ['x', 'd', 'w', 'i']);
assert.equal(b.summary, '✋ 1  ✓ 1  ✦ 1');

// herdr's snapshot: its workspace's name as the label, unknown as idle
const snap = {
    workspaces: [{workspace_id: 'w1', label: 'api'}],
    agents: [{pane_id: 'w1:p1', workspace_id: 'w1', agent: 'claude', agent_status: 'unknown'}],
};
assert.deepEqual(herdrItems(snap), [{session: 'w1', label: 'api', block: 'w1:p1', state: 'idle', app: 'claude', herdr: true}]);
assert.deepEqual(herdrItems(null), []);

assert.ok(isHerdrClient(['herdr']) && isHerdrClient(['/home/me/.local/bin/herdr', '--config', 'x']));
assert.ok(isHerdrClient(['herdr', 'session', 'attach', 'work']));
assert.ok(!isHerdrClient(['herdr', 'server']) && !isHerdrClient(['herdr', '--machine', 'nuc', 'agent', 'list']));
assert.ok(!isHerdrClient(['vim', 'herdr']));
console.log('ok');
