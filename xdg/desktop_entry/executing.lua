local split_string_to_args = function(command_string)
    local args = {}
    command_string = command_string .. "\\\"\\\""
    for regular, escaped in command_string:gmatch("(.-)\\\"(.-)\\\"") do
        append(args, regular:split(" "))
        if escaped == "" then break end
        escaped = escaped:gsub("\\([\\$`])", "%1")
        table.insert(args, escaped)
    end
    return args
end

local expand_field_codes = function(args, entry_info, files)
    local entry = entry_info.data
    local single_command = {}
    for _, arg in ipairs(args) do
        arg = arg:gsub("%%[dDnNvm]", "") --getting rid of deprecated codes
        arg = arg:gsub("%%%%", "%")
        arg = arg:gsub("%%c", entry["Name"]["base"])
        arg = arg:gsub("%%k", tostring(entry_info.path))

        if arg:find("%%i") then
            local icon = entry["Icon"]
            if icon == nil then goto continue end
            table.insert(single_command, "--icon")
            table.insert(single_command, entry["Icon"])
        end
        table.insert(single_command, arg)
        ::continue::
    end
    for index, arg in ipairs(single_command) do
        if (arg:find("%%[fu]")) then
            local returns = {}
            for _, file in ipairs(files) do
                local copy = {}
                for i, c_arg in ipairs(single_command) do
                    if i == index then
                        c_arg = c_arg:gsub("%%[fu]", file)
                    end
                    table.insert(copy, c_arg)
                end
                table.insert(returns, copy)
            end
            return returns
        end
        if (arg:find("%%[FU]")) then
            local final_command = {}
            for i, v in ipairs(single_command) do
                if i < index then
                    table.insert(final_command, v)
                else
                    break
                end
            end
            for _, file in ipairs(files) do
                table.insert(final_command, file)
            end
            for i, v in ipairs(single_command) do
                if i > index then
                    table.insert(final_command, v)
                else
                    break
                end
            end
            return { final_command }
        end
    end
    return { single_command }
end

local open_with_exec = function(entry_info, files, force_term)
    local entry = entry_info.data
    local parts = split_string_to_args(entry["Exec"])
    parts[1] = get_nix_command(parts[1])
    if entry["Terminal"] == true or force_term then
        parts = append({ get_nix_command("xdg-terminal-exec") }, parts)
    end
    local results = expand_field_codes(parts, entry_info, files)
    for _, v in ipairs(results) do
        for _,v_content in ipairs(v) do
            v_content = ya.quote(v_content):gsub(" ", "\\ ")
        end
        local args_string = mergeList(v, " ")
        dbg(dump(args_string)) 
        ya.emit("shell", { args_string , orphan = true})
    end
end

local desktop_id_to_dbus = function(id)
    return "/" .. id:gsub("%.desktop", ""):gsub("%.", "/")
end

local open_with_dbus = function(entry_info, files)
    local file_array = "["
    for index, file in ipairs(files) do
        file_array = file_array .. "'file://" .. file .. "'"
        if index < #files then
            file_array = file_array .. " "
        end
    end
    file_array = file_array .. "]"
    local _, err = Command(get_nix_command("gdbus"))
        :arg({ "call", "--session", "--dest" })
        :arg(entry_info.id:gsub("%.desktop", ""))
        :arg("--object-path")
        :arg(desktop_id_to_dbus(entry_info.id))
        :arg({ "--method", "org.freedesktop.Application.Open", })
        :arg(file_array)
        :arg(
            "{'desktop-startup-id': <'" .. (os.getenv("DESKTOP_STARTUP_ID") or "") ..
            "'>,'activation-token': <'" .. (os.getenv("XDG_ACTIVATION_TOKEN") or "") .. "'>}"
        )
        :stdin(Command.PIPED)
        :stdout(Command.PIPED)
        :spawn()
    if err then
        error(tostring(err))
        dbgerr("Failed to dbus launch: " .. desktop_id_to_dbus(entry_info.id) .. " with error: " .. tostring(err))
    end
end

function execute_desktop_entry(entry_info, files, force_term)
    local entry = entry_info.data
    if entry["DBusActivatable"] then
        open_with_dbus(entry_info, files)
    else
        open_with_exec(entry_info, files, force_term)
    end
end

function check_exec(entry_data)
    if entry_data["TryExec"] == nil then return true end
    local parts = split_string_to_args(entry_data["TryExec"])
    local command, args = first(parts)
    if command == "yazi" then return true end --workaround for basically bugging out yazi
    local status, err = Command(command):arg(args):status()
    if status ~= 0 or err then
        return false
    end
    return true
end
