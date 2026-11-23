-- A copy of islandStatusScript in IslandModel.swift: keep the two in step
-- Prints one JSON line with every pane's program status, then again on each change.
-- `visible` is the session the Rex app last showed, or nil until you switch sessions.
local visible

local function snapshot()
  local items = {}
  -- attach_all also picks up sessions created since the last snapshot
  local all = rex.call("session.attach_all", { event_scope = "session" }) or {}
  for _, s in ipairs(all.sessions or {}) do
    local blocks = rex.call("session.list_blocks", { session_id = s.session_id }) or {}
    for _, b in ipairs(blocks.blocks or {}) do
      if b.placement == "placed" then
        local st = rex.call("block.method", { session_id = s.session_id, block_id = b.block_id, method = "program_status" }) or {}
        for _, r in ipairs(st.records or {}) do
          if r.id == nil then
            items[#items + 1] = {
              session = s.session_id, label = s.label, block = b.block_id,
              state = r.state, kind = r.kind, app = r.effective_app, msg = r.msg, updated = r.updated_at,
            }
          end
        end
      end
    end
  end
  -- an empty Lua table encodes as {}, so spell out the empty list
  print((rex.json.encode({ items = items, visible = visible }):gsub('"items":{}', '"items":[]')))
end

local pending = false
local function changed()
  if pending then return end
  pending = true
  rex.after(0.2, function() pending = false; snapshot() end)
end

for _, ev in ipairs({ "terminal.program_status_changed", "terminal.program_status_removed",
  "session_label_changed", "block_closed", "session_created", "session_destroyed" }) do
  rex.on(ev, changed)
end

-- ponytail: Rex has no "session shown" event, but the app re-sends a session's terminal sizes
-- each time it shows it, so the last session the app resized is the one on screen
rex.on("terminal.size_changed", function(ctx, ev)
  for _, c in ipairs((rex.call("client.list") or {}).clients or {}) do
    if c.client_id == ev.owner and c.info.kind == "app" and visible ~= ctx.session_id then
      visible = ctx.session_id
      changed()
    end
  end
end)
snapshot()
