function first(list)
    local first = table.unpack(list, 1, 1)
    local remainder = { table.unpack(list, 2) }
    return first, remainder
end

function append(list, append)
    for _, v in ipairs(append) do
        table.insert(list, v)
    end
    return list
end

function contains(list, search)
    for _, v in ipairs(list) do
        if v == search then return true end
    end
    return false
end

function mergeList(list, seperator)
    local full_string = ""
    for index, value in ipairs(list) do
        full_string = full_string .. value
        if index ~= #list then
            full_string = full_string .. seperator
        end
    end
    return full_string
end