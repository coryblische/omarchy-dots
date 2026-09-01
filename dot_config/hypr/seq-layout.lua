-- Ultrawide sequence: 1 full, 2 half, 3 thirds,
-- 4 under window 1, 5 under 2, 6 under 3. 7th opens on the next workspace.

local MAX = 6
local order = {}

local function ws_key(workspace)
  if not workspace then
    return nil
  end
  return tostring(workspace.id or workspace)
end

local function ensure_order(workspace, targets)
  local key = ws_key(workspace)
  if not key then
    return {}
  end
  order[key] = order[key] or {}
  local seen = {}
  for _, addr in ipairs(order[key]) do
    seen[addr] = true
  end
  local present = {}
  for _, target in ipairs(targets) do
    local win = target.window
    if win and win.address then
      present[win.address] = true
      if not seen[win.address] then
        table.insert(order[key], win.address)
        seen[win.address] = true
      end
    end
  end
  local kept = {}
  for _, addr in ipairs(order[key]) do
    if present[addr] then
      table.insert(kept, addr)
    end
  end
  order[key] = kept
  return order[key]
end

local function sort_targets(ctx)
  local workspace = ctx.targets[1] and ctx.targets[1].window and ctx.targets[1].window.workspace
  local list = ensure_order(workspace, ctx.targets)
  local rank = {}
  for i, addr in ipairs(list) do
    rank[addr] = i
  end
  local targets = {}
  for _, t in ipairs(ctx.targets) do
    table.insert(targets, t)
  end
  table.sort(targets, function(a, b)
    local wa = a.window
    local wb = b.window
    local ra = (wa and rank[wa.address]) or (wa and wa.stable_id) or 9999
    local rb = (wb and rank[wb.address]) or (wb and wb.stable_id) or 9999
    if ra == rb and wa and wb then
      return (wa.stable_id or 0) < (wb.stable_id or 0)
    end
    return ra < rb
  end)
  return targets
end

local function place_rows(ctx, box, targets)
  local n = #targets
  if n == 0 then
    return
  end
  if n == 1 then
    targets[1]:place(box)
    return
  end
  -- Earliest window stays at the top. Newer ones stack below.
  local h = box.h / n
  for i, target in ipairs(targets) do
    target:place({
      x = box.x,
      y = box.y + (i - 1) * h,
      w = box.w,
      h = h,
    })
  end
end

hl.layout.register("seq", {
  recalculate = function(ctx)
    local n = #ctx.targets
    if n == 0 then
      return
    end
    local targets = sort_targets(ctx)

    if n == 1 then
      targets[1]:place(ctx.area)
      return
    end

    if n == 2 then
      for i, target in ipairs(targets) do
        target:place(ctx:column(i, 2))
      end
      return
    end

    local cols = { {}, {}, {} }
    for i, target in ipairs(targets) do
      table.insert(cols[((i - 1) % 3) + 1], target)
    end
    for c = 1, 3 do
      if #cols[c] > 0 then
        place_rows(ctx, ctx:column(c, 3), cols[c])
      end
    end
  end,
})

local function tiled_count(workspace)
  if not workspace then
    return 0
  end
  local n = 0
  for _, win in ipairs(hl.get_workspace_windows(workspace)) do
    if not win.floating and not win.hidden then
      n = n + 1
    end
  end
  return n
end

local function next_uw_workspace(current_id)
  for id = current_id + 1, 9 do
    local ws = hl.get_workspace(id)
    if not ws or tiled_count(ws) == 0 then
      return id
    end
  end
  for id = 1, current_id - 1 do
    local ws = hl.get_workspace(id)
    if not ws or tiled_count(ws) == 0 then
      return id
    end
  end
  return nil
end

local function overflow(win)
  if not win or win.floating or win.hidden then
    return
  end
  local ws = win.workspace
  if not ws or ws.special then
    return
  end
  local id = ws.id
  if id < 1 or id > 9 then
    return
  end
  if tiled_count(ws) <= MAX then
    return
  end
  local dest = next_uw_workspace(id)
  if not dest then
    return
  end
  hl.dispatch(hl.dsp.window.move({ workspace = tostring(dest), follow = true, window = win }))
  hl.dispatch(hl.dsp.focus({ workspace = tostring(dest) }))
end

hl.on("window.open", function(win)
  pcall(overflow, win)
end)
