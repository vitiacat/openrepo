local rcc_utils = {}
local component = require('component')

function rcc_utils.Split(s, delimiter)
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

function rcc_utils.cfgParse(cfg)
    local parsedCfg = {}
    for line in cfg:lines() do
        local a = rcc_utils.Split(line, '=')
        if #a < 2 then
            error('cfg parse error')
        end
        parsedCfg[a[1]] = a[2]
    end
    return parsedCfg;
end

function rcc_utils.cfgSave(table, path)
    local file = io.open(path, 'w')
    for key, value in pairs(table) do
        file:write(key..'='..value..'\n')
    end
    file:close()
end

function rcc_utils.indexOf(array, key)
    local i = 1
    for k, _ in pairs(array) do
        if k == key then
            return i
        end
        i = i + 1
    end
    return nil
end

function rcc_utils.HasValue(tab, val)
    for _, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end


return rcc_utils