local is_valid_entry = function(entry)
    if entry["Type"] ~= "Application" then return false end
    if entry["Name"] == nil then return false end
    return true
end

function should_show_entry(entry, mimetype)
    local valid = is_valid_entry(entry)
    if not valid then return false end
    if entry["NoDisplay"] then return false end
    if entry["Hidden"] then return false end
    if entry["OnlyShowIn"] ~= nil then
        local current_desktop = os.getenv("XDG_CURRENT_DESKTOP")
        local only_shows = entry["OnlyShowIn"]
        if not contains(only_shows, current_desktop) then return false end
    end
    if entry["NotShowIn"] ~= nil then
        local current_desktop = os.getenv("XDG_CURRENT_DESKTOP")
        local dont_shows = entry["NotShowIn"]
        if contains(dont_shows, current_desktop) then return false end
    end
    if entry["MimeType"] ~= nil then
        if not contains(entry["MimeType"], mimetype) then return false end
    end
    return true
end