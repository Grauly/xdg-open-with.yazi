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
    local search_pattern = key .. "%[(.-)%]=(.*)";
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

local parse_desktop_entry_string_list_raw = function(raw)
    if raw == nil then return nil end
    local splits = raw:escaped_split(";", "\\")
    local strings = {}
    for _, split in ipairs(splits) do
        split = split:gsub("\\;", ";")
        table.insert(strings, parse_desktop_entry_string_raw(split))
    end
    return strings
end

local parse_desktop_entry_string_list = function(entry_lines_list, key)
    return parse_desktop_entry_string_list_raw(retrieve_desktop_entry_value(entry_lines_list, key))
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
        raw[k] = parse_desktop_entry_string_list_raw(v)
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

function parse_desktop_entry_key(entry_lines_list, data, key, type)
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
        dbgerr("attempted to parse a unknown type: " .. type .. " for key: " .. key)
    end
end