function notify(content, level)
    ya.notify {
        title = Plugin_Name,
        content = content,
        level = level,
        timeout = 5
    }
end

function info(content)
    notify(content, "info")
end

function error(content)
    notify(content, "error")
end

function dbg(content)
    ya.dbg(Log_Prefix .. content)
end

function dbgerr(content)
    ya.err(Log_Prefix .. content)
end