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