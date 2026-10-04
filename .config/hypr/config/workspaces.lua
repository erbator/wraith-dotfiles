-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Generated from WORKSPACE_LAYOUT in variables.lua; edit the layout there.
-- Only the first workspace of each monitor is that monitor's default.
for _, entry in ipairs(WORKSPACE_LAYOUT) do
    for i, id in ipairs(entry.workspaces) do
        hl.workspace_rule({
            workspace  = tostring(id),
            monitor    = entry.monitor,
            default    = (i == 1),
            persistent = true,
        })
    end
end

-- For other layouts such as scrolling, add a rule on top, e.g.
-- hl.workspace_rule({ workspace = "2", layout = "scrolling" })
