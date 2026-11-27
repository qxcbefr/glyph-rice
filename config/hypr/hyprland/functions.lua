local vars = require("variables")

local function wsaction(action, range, i)
    return function()
        local activews = hl.get_active_workspace()
        if activews then
            local id = activews.id
            local s  = (i - 1) * 10 + (id % 10)
            local t  = math.floor((id - 1) / 10) * 10 + i
            local z  = (range == "group") and s or t

            if action == "move" then
                return hl.dispatch(hl.dsp.window.move({ workspace = z }))
            else
                return hl.dispatch(hl.dsp.focus({ workspace = z }))
            end
        end
    end
end

local function resize_by_screen(x, y)
    local screen = hl.get_active_monitor()
    if screen and type(screen.width) == "number" and type(screen.height) == "number" then
        if not (x == 0 and y == 0) then
            local w = (x and x > 0) and math.floor(screen.width * x / 100) or screen.width
            local h = (y and y > 0) and math.floor(screen.height * y / 100) or screen.height
            return { x = w, y = h, relative = false }
        end
    end
end

local function resize_active_window(x, y)
    local win = hl.get_active_window()
    if win and win.size then
        local w = (win.size.x * (x / 100)) or 800
        local h = (win.size.y * (y / 100)) or 600

        return { x = w, y = h, relative = true }
    end
end

local function resizer(window, pattern, x_percent, y_percent, actions, exact)
    if (window and window.title) and string.find(window.title, pattern, 1, exact) then
        local disp = (type(actions) == "table") and actions or { actions }
        for _, x in ipairs(disp) do
            hl.dispatch(x)
        end

        hl.dispatch(hl.dsp.window.resize(resize_by_screen(x_percent, y_percent)))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "keep_aspect_ratio", value = "true" }))
    end
end

local function move_actions(win)
    local screen = hl.get_active_monitor()

    if screen and screen.width and screen.height and win and win.size then
        local monitor_height = screen.height / screen.scale
        local monitor_width  = screen.width / screen.scale

        local scale_factor   = (monitor_height / 4) / win.size.y

        local target_width   = win.size.x * scale_factor
        local target_height  = win.size.y * scale_factor

        local x_resize       = math.floor(math.max(200, target_width))
        local y_resize       = math.floor(math.max(150, target_height))

        local offset         = math.min(monitor_width, monitor_height) * 0.03

        local move_x         = math.floor(screen.x + monitor_width - x_resize - offset)
        local move_y         = math.floor(screen.y + monitor_height - y_resize - offset)

        return {
            hl.dsp.window.resize({ x = x_resize, y = y_resize, window = win }),
            hl.dsp.window.move({ x = move_x, y = move_y, relative = false, window = win }),
        }
    end
end

-- special ws: open/close, and if it is empty, launch its app from vars.apps (caelestia toggle replacement).
-- we read apps on keypress, not at load: user.lua loads after the keybinds and changes them there
local function toggle_special(name)
    return function()
        local cmd = vars.apps[name]
        for _, ws in ipairs(hl.get_workspaces()) do
            if ws.name == "special:" .. name and ws.windows > 0 then cmd = nil end
        end
        -- show first, launch after: hypr opens the window where focus was at launch time,
        -- and in the reverse order it would hide the workspace as soon as the window appears
        hl.dispatch(hl.dsp.workspace.toggle_special(name))
        if cmd then hl.exec_cmd(cmd) end
    end
end

-- hypr has no minimize: tag the window and park it on a special workspace, the same key
-- brings the parked windows back to the active one (wiki: lua code snippets)
local function minimize()
    local active = hl.get_active_workspace()
    local parked = false
    for _, ws in ipairs(hl.get_workspaces()) do
        if ws.name == "special:minimized" and ws.windows > 0 then parked = true end
    end

    if parked and active and active.name ~= "special:minimized" then
        hl.dispatch(hl.dsp.window.move({ workspace = active, window = "tag:minimized" }))
        hl.dispatch(hl.dsp.window.clear_tags({ window = "tag:minimized" }))
        return
    end

    local win = hl.get_active_window()
    if win then
        hl.dispatch(hl.dsp.window.tag({ tag = "minimized", window = win }))
        hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", follow = false }))
    end
end

-- hide every window on the current workspace (show desktop): they go to a special workspace,
-- the same key moves them back. Addresses are collected first: dispatching invalidates the list
local function hide_all()
    local active = hl.get_active_workspace()
    if not active then return end

    -- a selector like tag:hidden only ever moves the first match -- walk the addresses instead
    local parked = {}
    for _, win in ipairs(hl.get_windows() or {}) do
        for _, tag in ipairs(win.tags or {}) do
            if tag == "hidden" then
                table.insert(parked, win.address)
                break
            end
        end
    end

    if #parked > 0 then
        for _, address in ipairs(parked) do
            local win = "address:" .. address
            hl.dispatch(hl.dsp.window.move({ workspace = active, window = win }))
            hl.dispatch(hl.dsp.window.clear_tags({ window = win }))
        end
        return
    end

    local targets = {}
    for _, win in ipairs(hl.get_windows() or {}) do
        if win.mapped and not win.hidden and win.workspace and win.workspace.id == active.id then
            table.insert(targets, win.address)
        end
    end

    for _, address in ipairs(targets) do
        local win = "address:" .. address
        hl.dispatch(hl.dsp.window.tag({ tag = "hidden", window = win }))
        hl.dispatch(hl.dsp.window.move({ workspace = "special:hidden", follow = false, window = win }))
    end
end

-- gpu-screen-recorder screen capture: the same keybind again -- stop
local function record(region, sound)
    return function()
        local mon = hl.get_active_monitor()
        local w   = region and '-w region -region "$(slurp -f %wx%h+%x+%y)"' or "-w " .. (mon and mon.name or "region")
        hl.exec_cmd("pkill -INT -f '^gpu-screen-recorder' || gpu-screen-recorder " .. w ..
            (sound and " -a default_output" or "") .. ' -o "$(xdg-user-dir VIDEOS)/rec-$(date +%F_%H-%M-%S).mp4"')
    end
end

return {
    hide_all             = hide_all,
    minimize             = minimize,
    toggle_special       = toggle_special,
    record               = record,
    resizer              = resizer,
    resize_by_screen     = resize_by_screen,
    resize_active_window = resize_active_window,
    wsaction             = wsaction,
    move_actions         = move_actions,
}
