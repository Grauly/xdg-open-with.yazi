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
    parse_desktop_entry_key(desktop_entry_lines, data, "Actions", "l")
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
    local header = "Desktop Action " .. action_name
    local raw_action = entry_data[header]
    local action_data = {}
    parse_desktop_entry_key(raw_action, action_data, "Name", "s")
    parse_desktop_entry_key(raw_action, action_data, "Icon", "i")
    parse_desktop_entry_key(raw_action, action_data, "Exec", "s")
    return action_data
end

local parse_desktop_entry_actions = function(spec_data, entry_data)
    local action_names = spec_data["Actions"]
    if action_names == nil then return nil end
    local actions = {}
    for _, v in ipairs(action_names) do
        actions[v] = parse_desktop_entry_action(v, entry_data)
    end
    return actions
end

function read_desktop_entry(id, abs_path)
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
        dbgerr("Attempted to parse invalid desktop entry (invalid header): " ..
            id .. " at: " .. tostring(abs_path) .. " with header: " .. actual_lines[1])
        return {}
    end
    local entry_data = {}
    local current_group = ""
    for _, line in ipairs(actual_lines) do
        local start, stop, find = line:find("%[(.*)%]")
        if start == 1 then
            current_group = find
            entry_data[current_group] = {}
        end
        table.insert(entry_data[current_group], line)
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