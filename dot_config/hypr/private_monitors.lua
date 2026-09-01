-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 1
local omarchy_monitor_scale = "auto"

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Configure a specific monitor.
hl.monitor({ output = "DP-3", mode = "3440x1440@164.90Hz", position = "0x0", scale = 1, transform = 0 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
hl.monitor({ output = "DP-2", mode = "2560x1440@60.00Hz", position = "3440x0", scale = 1, transform = 1 })

-- Ultrawide owns 1-9 so new numbered workspaces stay on primary.
-- Portrait is workspace 10 (Super+0).
for workspace = 1, 9 do
  hl.workspace_rule({
    workspace = tostring(workspace),
    monitor = "DP-3",
    default = workspace == 1,
    persistent = workspace == 1,
    layout = "lua:seq",
  })
end
hl.workspace_rule({
  workspace = "10",
  monitor = "DP-2",
  default = true,
  persistent = true,
  layout_opts = { direction = "down" },
})

