local header_name = "xdg-open-with"
local log_prefix = "[" .. header_name .. "] "

local notify = function(content, level)
    ya.notify {
        title = header_name,
        content = content,
        level = level,
        timeout = 5
    }
end

local info = function(content)
    notify(content, "info")
end

local error = function(content)
    notify(content, "error")
end

local dbg = function(content)
    ya.dbg(log_prefix .. content)
end

local dbgerr = function(content)
    ya.err(log_prefix .. content)
end

function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then k = '"' .. k .. '"' end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function string:endswith(suffix)
    return self:sub(- #suffix) == suffix
end

function string:beginswith(prefix)
    return self:sub(#prefix) == prefix
end

function string:split(split)
    self = self..split
    local results = {}
    for match, delimiter in self:gmatch("(.-)("..split..")") do
        table.insert(results, match)
        if (delimiter == "") then
            return results
        end
    end
    return results
end

function mergeTables(a, b, replace)
    local result = {}
    for k, v in pairs(a) do
        result[k] = v
    end
    for k, v in pairs(b) do
        if ((result[k] == nil) or (replace)) then
            result[k] = v
        end
    end
    return result
end

local retrieve_data_dirs = function()
    return os.getenv("XDG_DATA_DIRS"):split(":")
end

local get_files = function(url, opts)
    local files, err = fs.read_dir(url, opts)
    if err then
        dbgerr("Error accessing: " .. dump(url) .. " : " .. dump(err))
        return {}
    end
    return files
end

local url_to_desktop_id = function(strip_prefix, url)
    local url_string = tostring(url:strip_prefix(strip_prefix))
    url_string = url_string:gsub("-", "_")
    url_string = url_string:gsub("/", "-")
    return url_string
end

local collect_desktop_entries
collect_desktop_entries = function(applications_url, search_url)
    local files = get_files(search_url, {})
    local applications = {}
    for _, file in ipairs(files) do
        if (file.cha.is_dir) then
            local sub_applications = collect_desktop_entries(Url(search_url):join(file.name))
            applications = mergeTables(applications, sub_applications, false)
        else
            if file.name:endswith(".desktop") then
                applications[url_to_desktop_id(applications_url, file.url)] = file.url
            end
        end
    end
    return applications
end

local find_desktop_entries = function(dir)
    local search_location = Url(dir):join("applications")
    return collect_desktop_entries(search_location, search_location)
end

local find_all_desktop_entries = function()
    local data_dirs = retrieve_data_dirs()
    local desktop_entries = {}
    for _, v in ipairs(data_dirs) do
        local entries = find_desktop_entries(v)
        desktop_entries = mergeTables(desktop_entries, entries, false)
    end
    return desktop_entries
end

local update_desktop_entries = ya.sync(function(self, entries)
    local raw_display_entries = {}
    for k, _ in pairs(entries) do
        raw_display_entries[#raw_display_entries + 1] = k
    end
    self.desktop_entries = raw_display_entries
    ya.render()
end)

--cursor ops
local update_cursor = ya.sync(function(self, offset)
    local new_cursor = self.cursor + offset
    local max_pos = (#self.desktop_entries or 0)
    if (new_cursor < 0) then
        self.cursor = 0
    elseif (new_cursor > max_pos) then
        self.cursor = max_pos
    else
        self.cursor = new_cursor
    end
end)

--ui open/close
local open_ui_if_not_open = ya.sync(function(self)
    if not self.children then
        self.children = Modal:children_add(self, 10)
    end
    ya.render()
end)

local close_ui_if_open = ya.sync(function(self)
    if self.children then
        Modal:children_remove(self.children)
        self.children = nil
    end
    ya.render()
end)

--shamelessly stolen from https://github.com/yazi-rs/plugins/tree/main/chmod.yazi
local selected_or_hovered = ya.sync(function()
    local tab, paths = cx.active, {}
    for _, u in pairs(tab.selected) do
        paths[#paths + 1] = tostring(u)
    end
    if #paths == 0 and tab.current.hovered then
        paths[1] = tostring(tab.current.hovered.url)
    end
    return paths
end)

--requires aync context to run

local sc = function(on, run)
    return { on = on, run = run }
end


local M = {
    keys = {
        sc("q", "quit"),
        sc("<Escape>", "quit"),
        sc("<Up>", "up"),
        sc("<Down>", "down"),
        sc("<Enter>", "open")
    },
    cursor = 0,
    desktop_entries = {}
}

--entry point, async
function M:entry(job)
    open_ui_if_not_open()
    local entries = find_all_desktop_entries()
    update_desktop_entries(entries)
    self.user_input(self)
end

function M:user_input()
    while true do
        local action = (self.keys[ya.which { cands = self.keys, silent = true }] or { run = "invalid" }).run
        if action == "quit" then
            close_ui_if_open()
            return
        end
        self.act_user_input(self, action)
    end
end

function M:act_user_input(action)
    if action == "up" then
        update_cursor(-1)
    elseif action == "down" then
        update_cursor(1)
    end
end

-- Modal functions
function M:new(area)
    self:layout(area)
    return self
end

-- Not a modal function but a helper to get the layout
function M:layout(area)
    local h_chunks = ui.Layout()
        :direction(ui.Layout.HORIZONTAL)
        :constraints({
            ui.Constraint.Percentage(25),
            ui.Constraint.Percentage(50),
            ui.Constraint.Percentage(25)
        })
        :split(area)
    local v_chunks = ui.Layout()
        :direction(ui.Layout.VERTICAL)
        :constraints({
            ui.Constraint.Percentage(10),
            ui.Constraint.Percentage(80),
            ui.Constraint.Percentage(10)
        })
        :split(h_chunks[2])

    self.draw_area = v_chunks[2]
end

function M:reflow()
    return { self }
end

-- actually draw the content, is synced, so cannot use Command
function M:redraw()
    local rows = {}
    for k, v in pairs(self.desktop_entries) do
        rows[k] = ui.Row { v, "" }
    end
    -- basically stolen from https://github.com/yazi-rs/plugins/blob/a1738e8088366ba73b33da5f45010796fb33221e/mount.yazi/main.lua#L144
    return {
        ui.Clear(self.draw_area),
        ui.Border(ui.Border.ALL)
            :area(self.draw_area)
            :type(ui.Border.ROUNDED)
            :style(ui.Style():fg("blue"))
            :title(ui.Line("XDG-Mimetype"):align(ui.Line.CENTER)),
        ui.Table(rows)
            :area(self.draw_area:pad(ui.Pad(1, 2, 1, 2)))
            :header(ui.Row({ "Dir?", "name" }):style(ui.Style():bold()))
            :row(self.cursor)
            :row_style(ui.Style():fg("blue"):underline())
            :widths {
                ui.Constraint.Percentage(90),
                ui.Constraint.Percentage(10),
            },
    }
end

return M
