function mergeTables(a, b, replace)
    local result = {}
    for k, v in pairs(a) do
        result[k] = v
    end
    for k, v in pairs(b) do
        if ((result[k] == nil) or (replace)) then
            result[k] = v
        end
    end
    return result
end

function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            local k_tmp = k
            if type(k) ~= 'number' then k_tmp = '"' .. k .. '"' end
            s = s .. '[' .. k_tmp .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end