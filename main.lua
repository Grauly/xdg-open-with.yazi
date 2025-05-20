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
    return self:sub(1, #prefix) == prefix
end

function string:split(split)
    if not self:endswith(split) then
        self = self .. split
    end
    local results = {}
    for match, delimiter in self:gmatch("(.-)(" .. split .. ")") do
        table.insert(results, match)
        if (delimiter == "") then
            return results
        end
    end
    return results
end

function string:escaped_split(split, escape_char)
    if not self:endswith(split) then
        self = self .. split
    end
    local results = {}
    for match, leader, delimiter in self:gmatch("(.-)([^" .. escape_char .. "])(" .. split .. ")") do
        table.insert(results, match .. leader)
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

function first(list)
    local first = table.unpack(list, 1, 1)
    local remainder = { table.unpack(list, 2) }
    return first, remainder
end

local get_files = function(url, opts)
    local files, err = fs.read_dir(url, opts)
    if err then
        dbgerr("Error accessing: " .. dump(url) .. " : " .. dump(err))
        return {}
    end
    return files
end

local exists_file = function(location)
    if (type(location) ~= "string") then
        location = tostring(location)
    end
    local file = io.open(location, "rb")
    if file then file:close() end
    return file ~= nil
end

local get_file = function(location)
    if (type(location) ~= "string") then
        location = tostring(location)
    end
    if not exists_file(location) then
        return {}
    end
    local lines = {}
    for line in io.lines(location) do
        lines[#lines + 1] = line
    end
    return lines
end

--needs a plugin named "nix-commands" with a database of commands
local get_nix_command = function(command)
    if (command:beginswith("/")) then return command end

    local loaded, content = pcall(require, "nix-commands")
    if not loaded then
        ya.err(content)
        return command
    end
    if not content.commands then
        ya.err("nix-commands does not have a commands section, defaulting")
        return command
    end
    local nix_command = content.commands[command]
    if not nix_command then
        ya.err("nix-commands does not have a \"" .. command .. "\" defined")
        return command
    end
    return nix_command
end

--end of utils section

--desktop entry file operations

local retrieve_data_dirs = function()
    return os.getenv("XDG_DATA_DIRS"):split(":")
end

local url_to_desktop_id = function(strip_prefix, url)
    local url_string = tostring(url:strip_prefix(strip_prefix))
    url_string = url_string:gsub("-", "_")
    url_string = url_string:gsub("/", "-")
    return url_string
end

local desktop_id_to_dbus = function(id)
    return "/" .. id:gsub("%.desktop"):gsub(".", "/")
end

local collect_desktop_entries
collect_desktop_entries = function(applications_url, search_url)
    --should be using glob = "*.desktop", but it just does not work
    local files = get_files(search_url, {})
    local applications = {}
    for _, file in ipairs(files) do
        if (file.cha.is_dir) then
            local sub_applications = collect_desktop_entries(Url(search_url):join(file.name))
            applications = mergeTables(applications, sub_applications, false)
        else
            --hence, this workaround
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

--desktop entry parsing operations

local retrieve_desktop_entry_value = function(entry_lines_list, key)
    local search_pattern = key .. "=(.*)";
    for _, v in ipairs(entry_lines_list) do
        local start, _, found_value = v:find(search_pattern)
        if start == 1 then
            return found_value
        end
    end
    return nil
end

local retrieve_localized_desktop_entry_value = function(entry_lines_list, key)
    local base = retrieve_desktop_entry_value(entry_lines_list, key)
    if base == nil then return nil end
    local result = {}
    result["base"] = base
    local search_pattern = key .. "[(.-)]=(.*)";
    for _, v in ipairs(entry_lines_list) do
        local start, _, found_key, found_value = v:find(search_pattern)
        if start == 1 then
            result[found_key] = found_value
        end
    end
    return result
end

local parse_desktop_entry_string_raw = function(raw)
    if raw == nil then return nil end
    raw = raw:gsub("\\s", " ")
    raw = raw:gsub("\\n", "\n")
    raw = raw:gsub("\\t", "\t")
    raw = raw:gsub("\\r", "\r")
    raw = raw:gsub("\\\\", "\\")
    return raw
end

local parse_desktop_entry_string = function(entry_lines_list, key)
    return parse_desktop_entry_string_raw(retrieve_desktop_entry_value(entry_lines_list, key))
end

local parse_desktop_entry_string_list = function(entry_lines_list, key)
    local raw = retrieve_desktop_entry_value(entry_lines_list, key)
    if raw == nil then return nil end
    local splits = raw:escaped_split(";", "\\")
    local strings = {}
    for _, split in ipairs(splits) do
        split = split:gsub("\\;", ";")
        table.insert(strings, parse_desktop_entry_string_raw(split))
    end
    return strings
end

local parse_desktop_entry_locale_string = function(entry_lines_list, key)
    local raw = retrieve_localized_desktop_entry_value(entry_lines_list, key)
    if raw == nil then return nil end
    for k, v in pairs(raw) do
        raw[k] = parse_desktop_entry_string_raw(v)
    end
    return raw
end

local parse_desktop_entry_locale_string_list = function(entry_lines_list, key)
    local raw = retrieve_localized_desktop_entry_value(entry_lines_list, key)
    if raw == nil then return nil end
    for k, v in pairs(raw) do
        raw[k] = parse_desktop_entry_string_list(v)
    end
    return raw
end

local parse_desktop_entry_iconstring = function(entry_lines_list, key)
    --I dont think I will?
    return nil
end

local parse_desktop_entry_boolean = function(entry_lines_list, key)
    local raw = retrieve_desktop_entry_value(entry_lines_list, key)
    if raw == nil then return nil end
    if raw == "true" then return true end
    if raw == "false" then return false end
    return nil
end

local parse_desktop_entry_numeric = function(entry_lines_list, key)
    local raw = retrieve_desktop_entry_value(entry_lines_list, key)
    if raw == nil then return nil end
    return tonumber(raw)
end

local parse_desktop_entry_key = function(entry_lines_list, data, key, type)
    if type == "s" then
        data[key] = parse_desktop_entry_string(entry_lines_list, key)
    elseif type == "l" then
        data[key] = parse_desktop_entry_string_list(entry_lines_list, key)
    elseif type == "ls" then
        data[key] = parse_desktop_entry_locale_string(entry_lines_list, key)
    elseif type == "lsl" then
        data[key] = parse_desktop_entry_locale_string_list(entry_lines_list, key)
    elseif type == "i" then
        data[key] = parse_desktop_entry_iconstring(entry_lines_list, key)
    elseif type == "b" then
        data[key] = parse_desktop_entry_boolean(entry_lines_list, key)
    elseif type == "n" then
        data[key] = parse_desktop_entry_numeric(entry_lines_list, key)
    else
        dbgerr("attempted to parse a unknown type: "..type.." for key: "..key)
    end
end

local parse_desktop_entry = function(desktop_entry_lines)
    local data = {}
    parse_desktop_entry_key(desktop_entry_lines, data, "Type", "s")
    parse_desktop_entry_key(desktop_entry_lines, data, "Version", "s")
    parse_desktop_entry_key(desktop_entry_lines, data, "Name", "ls")
    parse_desktop_entry_key(desktop_entry_lines, data, "GenericName", "ls")
    parse_desktop_entry_key(desktop_entry_lines, data, "NoDisplay", "b")
    parse_desktop_entry_key(desktop_entry_lines, data, "Comment", "ls")
    parse_desktop_entry_key(desktop_entry_lines, data, "Icon", "i")
    parse_desktop_entry_key(desktop_entry_lines, data, "Hidden", "b")
    parse_desktop_entry_key(desktop_entry_lines, data, "OnlyShowIn", "l")
    parse_desktop_entry_key(desktop_entry_lines, data, "NotShowIn", "l")
    parse_desktop_entry_key(desktop_entry_lines, data, "DBusActivatable", "b")
    parse_desktop_entry_key(desktop_entry_lines, data, "TryExec", "s")
    parse_desktop_entry_key(desktop_entry_lines, data, "Exec", "s")
    parse_desktop_entry_key(desktop_entry_lines, data, "Path", "s")
    parse_desktop_entry_key(desktop_entry_lines, data, "Terminal", "b")
    parse_desktop_entry_key(desktop_entry_lines, data, "Actions", "l") --TODO: parse the actual actions
    parse_desktop_entry_key(desktop_entry_lines, data, "MimeType", "l")
    parse_desktop_entry_key(desktop_entry_lines, data, "Categories", "l")
    parse_desktop_entry_key(desktop_entry_lines, data, "Implements", "l")
    parse_desktop_entry_key(desktop_entry_lines, data, "Keywords", "lsl")
    parse_desktop_entry_key(desktop_entry_lines, data, "StartupNotify", "b")
    parse_desktop_entry_key(desktop_entry_lines, data, "StartupWMClass", "s")
    parse_desktop_entry_key(desktop_entry_lines, data, "URL", "s")
    parse_desktop_entry_key(desktop_entry_lines, data, "PrefersNonDefaultGPU", "b")
    parse_desktop_entry_key(desktop_entry_lines, data, "SingleMainWindow", "b")
    return data
end

local parse_desktop_entry_action = function(action_name, entry_data)
    local header = "Desktop Action "..action_name
    local raw_action = entry_data[header]
    local action_data = {}
    parse_desktop_entry_key(raw_action, action_data, "Name", "s")
    parse_desktop_entry_key(raw_action, action_data, "Icon", "i")
    parse_desktop_entry_key(raw_action, action_data, "Exec", "s")
    return action_data
end

local parse_desktop_entry_actions = function(spec_data, entry_data)
    local action_names = spec_data["Actions"]
    local actions = {}
    for _,v in ipairs(action_names) do
        actions[v] = parse_desktop_entry_action(v, entry_data)
    end
    return actions
end

local read_desktop_entry = function(id, abs_path)
    local lines = get_file(abs_path)
    if (next(lines) == nil) then
        dbgerr("Attempted to read empty desktop entry: " .. id .. " at: " .. tostring(abs_path))
        return {}
    end
    local actual_lines = {}
    --erase all non actual data
    for _, v in ipairs(lines) do
        if v == "" then goto continue end
        if v:beginswith("#") then goto continue end
        table.insert(actual_lines, v)
        ::continue::
    end
    --parse to groups
    if actual_lines[1] ~= "[Desktop Entry]" then
        dbgerr("Attempted to parse invalid desktop entry (invalid header): " .. id .. " at: " .. tostring(abs_path))
        return {}
    end
    local entry_data = {}
    local current_group = ""
    for _, line in ipairs(actual_lines) do
        local find, name = line:find("%[(.*)%]")
        if find == 1 then
            current_group = name
            entry_data[name] = {}
        end
        entry_data[current_group]:insert(line)
    end
    local spec_data = parse_desktop_entry(entry_data["Desktop Entry"])
    local actions = parse_desktop_entry_actions(spec_data, entry_data)
    return {
        id = id,
        path = abs_path,
        data = spec_data,
        actions = actions,
        raw_data = entry_data
    }
end

local get_launch_command = function(entry)
    local entry_data = entry.data
    if entry_data["TryExec"] ~= nil then
        local tryExec = entry_data["TryExec"]
    end
    if entry_data["DBusActivatable"] then
        return {
            file_prefix = "'file://",
            file_suffix = "' ",
            prefix = "gdbus call --session --dest \"" ..
                entry.id:gsub(".desktop", "") ..
                "\" --object-path \"" .. desktop_id_to_dbus(entry.id) ..
                "\" --method \"org.freedesktop.Application.Open\" \"[",
            op = "%F",
            suffix = "]\" \"{'desktop-startup-id':<'" ..
                os.getenv("DESKTOP_STARTUP_ID") ..
                "'>,'activation-token':<'" .. os.getenv("XDG_ACTIVATION_TOKEN") .. "'>}"
        }
    else
        local exec_command = entry_data["Exec"]
        if (entry_data["Icon"] ~= nil) then
            exec_command = exec_command:gsub("%%i", "--icon " .. entry_data["Icon"])
        else
            exec_command = exec_command:gsub("%%i", "")
        end
        --meant to translate, but honestly not dealing with that
        exec_command = exec_command:gsub("%%c", entry_data["Name"])
        exec_command = exec_command:gsub("%%k", entry.abs_path)
        local prefix, op, suffix = exec_command:gmatch("(.-)(%%[uUfF])(.*)")
        return {
            file_prefix = "",
            file_suffix = "",
            prefix = prefix,
            op = op,
            suffix = suffix
        }
    end
end

local launch_command_to_command = function(launch_command, files)
    if launch_command == {} then return {} end

    local prefixes = launch_command.prefix:split(" ")
    local command = Command(get_nix_command(prefixes[1]))
    local _, prefix_args = first(prefixes)
    command = command:args(prefix_args)
    local launch_files = {}
    for i, f in ipairs(files) do
        launch_files[i] = launch_command.file_prefix .. tostring(f) .. launch_command.file_suffix
    end
    if (launch_command.op == "%u" or launch_command.op == "%f") then
        local file, _ = first(files)
        launch_files = { file }
    end
    command = command:args(launch_files):args(launch_command.suffix:split(" "))
    return command
end

local parse_string_to_command = function(command_string, files)
    local args = {}
    command_string = command_string .. "\\\"\\\""
    for regular, escaped, addenda in command_string:gmatch("(.-)\\\"(.-)([^\\])\\\"") do
        table.insert(args, regular)
        escaped = (escaped .. addenda):gsub("\\([\"])", "%1")
    end
    local pieces = command_string:split(" ")
    local first, rest = first(pieces)
    local args = {}
    for _, v in ipairs(rest) do
        if v:beginswith("%") then
            --todo handle the expansions and unescapes
            if (v:find("\\\"(.+)\\\"")) then

            end
        end
    end
    return Command(get_nix_command(first)):args(args)
end

local basic_exec_check = function(entry)
    local data = entry["data"]
    if data["TryExec"] ~= nil then
        local try_command = parse_string_to_command(data["TryExec"])
        local status, err = try_command:stdout(Command.PIPED):status()
        if (err) then
            return false
        end
        if status.success and status.code == 0 then
            return true
        end
    end
    if data["DBusActivatable"] == true then
        --we just pray, basically
        return true
    else
        return data["Exec"] ~= nil
    end
end

local is_valid_entry = function(entry)
    local data = entry["data"]
    if data["Type"] ~= "Application" then return false, entry end
    if data["Name"] == nil then return false, entry end
    return true
end

local should_show_entry = function(entry)
    local valid = is_valid_entry(entry)
    if not valid then return false end
    if entry["NoDisplay"] then return false end
    if entry["Hidden"] then return false end
    if entry["OnlyShowIn"] ~= nil then
        local current_desktop = os.getenv("XDG_CURRENT_DESKTOP")
        local only_shows = entry["OnlyShowIn"]:split(";")
        local should_show = false
        for _, v in ipairs(only_shows) do
            if v == current_desktop then
                should_show = true
                break
            end
        end
        if not should_show then
            return false
        end
    end
    if entry["NotShowIn"] ~= nil then
        local current_desktop = os.getenv("XDG_CURRENT_DESKTOP")
        local dont_shows = entry["NotShowIn"]:split(";")
        local should_show = true
        for _, v in ipairs(dont_shows) do
            if v == current_desktop then
                should_show = false
                break
            end
        end
        if not should_show then
            return false
        end
    end
    --TODO: look for Path and Terminal Keys for launch command
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
