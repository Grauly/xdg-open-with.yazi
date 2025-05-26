 function get_files(url, opts)
    local files, err = fs.read_dir(url, opts)
    if err then
        --dbgerr("Error accessing: " .. dump(url) .. " : " .. dump(err))
        return {}
    end
    return files
end

function exists_file(location)
    if (type(location) ~= "string") then
        location = tostring(location)
    end
    local file = io.open(location, "rb")
    if file then file:close() end
    return file ~= nil
end

function get_file(location)
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