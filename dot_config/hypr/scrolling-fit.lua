-- Ultrawide: 1 full, 2 half, 3+ thirds as columns (scroll right).
-- Portrait (90/270): same 1/2/3 as rows (scroll down).
-- Super+Shift+period stacks into the previous column/row.

local PORTRAIT_TRANSFORMS = { [1] = true, [3] = true }
local last_direction = {}

local function is_portrait(monitor)
  return monitor and PORTRAIT_TRANSFORMS[monitor.transform] == true
end

local function pos_xy(win)
  local at = win.at
  if type(at) ~= "table" then
    return nil, nil
  end
  return at.x or at[1], at.y or at[2]
end

local function strip_count(workspace)
  if not workspace then
    return 0
  end
  local portrait = is_portrait(workspace.monitor)
  local windows = hl.get_workspace_windows(workspace)
  local seen = {}
  local n = 0
  for _, win in ipairs(windows) do
    if not win.floating and not win.hidden then
      local x, y = pos_xy(win)
      local along = portrait and y or x
      if along then
        local key = math.floor((along + 24) / 48)
        if not seen[key] then
          seen[key] = true
          n = n + 1
        end
      end
    end
  end
  return n
end

local function apply_direction(workspace)
  if not workspace or workspace.special then
    return
  end
  -- Never stomp dwindle / lua:seq. A layout_opts-only rule replaces the
  -- whole workspace rule and snaps layout back to general.scrolling.
  if workspace.tiled_layout ~= "scrolling" then
    return
  end
  local dir = is_portrait(workspace.monitor) and "down" or "right"
  local key = (workspace.name and tostring(workspace.name)) or tostring(workspace.id)
  if last_direction[key] == dir then
    return
  end
  last_direction[key] = dir
  hl.workspace_rule({
    workspace = key,
    layout = "scrolling",
    layout_opts = { direction = dir },
  })
end

local function fit_workspace(workspace)
  if not workspace or workspace.special then
    return
  end
  if workspace.tiled_layout ~= "scrolling" then
    return
  end
  apply_direction(workspace)
  local n = strip_count(workspace)
  if n <= 1 then
    return
  end
  local width = (n == 2) and "0.5" or "0.333"
  local mon = workspace.monitor
  if mon then
    hl.dispatch(hl.dsp.focus({ monitor = mon.name }))
  end
  hl.dispatch(hl.dsp.layout("colresize all " .. width))
  -- Portrait rows should fill the tall screen. Ultrawide keeps extra columns on the tape.
  if is_portrait(workspace.monitor) then
    hl.dispatch(hl.dsp.layout("fit all"))
  end
end

local function fit_visible()
  local prev = hl.get_active_window()
  for _, ws in ipairs(hl.get_workspaces()) do
    if ws.visible then
      pcall(fit_workspace, ws)
    end
  end
  if prev then
    pcall(function()
      if prev.monitor then
        hl.dispatch(hl.dsp.focus({ monitor = prev.monitor.name }))
      end
    end)
  end
end

local timer = hl.timer(function()
  pcall(fit_visible)
end, { timeout = 80, type = "oneshot" })
timer:set_enabled(false)

local function schedule_fit()
  timer:set_timeout(80)
  timer:set_enabled(true)
end

hl.on("window.open", schedule_fit)
hl.on("window.close", schedule_fit)
hl.on("window.move_to_workspace", schedule_fit)
hl.on("workspace.active", schedule_fit)
hl.on("workspace.move_to_monitor", schedule_fit)
hl.on("config.reloaded", function()
  -- Do not wipe last_direction. Wiping retriggers workspace_rule and
  -- races the Super+L layout toggle.
  schedule_fit()
end)
hl.on("hyprland.start", schedule_fit)

pcall(fit_visible)
