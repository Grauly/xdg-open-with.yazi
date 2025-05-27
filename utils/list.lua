function first(list)
    local first = table.unpack(list, 1, 1)
    local remainder = { table.unpack(list, 2) }
    return first, remainder
end

function append(list, append)
    for _, v in ipairs(append) do
        table.insert(list, v)
    end
end

function contains(list, search)
    for _, v in ipairs(list) do
        if v == search then return true end
    end
    return false
end