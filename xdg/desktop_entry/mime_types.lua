local get_file_mime = function(file)
    local output, err = Command(get_nix_command("xdg-mime"))
        :arg({ "query", "filetype", tostring(file) })
        :stdout(Command.PIPED)
        :stdin(Command.PIPED)
        :output()
    if err then
        dbgerr(tostring(err))
        return "none"
    end
    return output.stdout:gsub("\n","")
end

function get_mime_organized_files(files)
    local mimed_files = {}
    for _, file in ipairs(files) do
        local mime = get_file_mime(file)
        if mimed_files[mime] == nil then
            mimed_files[mime] = {}
        end
        table.insert(mimed_files[mime], tostring(file))
    end
    return mimed_files
end
