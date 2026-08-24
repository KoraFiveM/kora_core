Locale = {}
Locale.__index = Locale

function Locale:new(props)
    local self = setmetatable({}, Locale)

    self.phrases = (props and props.phrases) or {}
    self.warnOnMissing = (props and props.warnOnMissing) or false
    self.currentLocale = (props and props.currentLocale) or 'en'

    return self
end

function Locale:getPhrase(path)
    local keys = self:strSplit(path, '.')
    local result = self.phrases

    for i = 1, #keys do
        if type(result) ~= 'table' then return nil end
        result = result[keys[i]]
    end

    return result
end

function Locale:interpPhrase(phrase, subs)
    if type(phrase) ~= 'string' then return phrase end

    for key, val in pairs(subs) do
        phrase = phrase:gsub('%%{' .. key .. '}', tostring(val))
    end

    return phrase
end

function Locale:t(path, subs)
    local translated = self:getPhrase(path)

    if translated ~= nil then
        return self:interpPhrase(translated, subs or {})
    end

    if self.warnOnMissing then
        print(('[LOCALE] Missing key: %s'):format(path))
    end

    return path
end

function Locale:strSplit(str, sep)
    local fields = {}

    str:gsub(string.format('([^%s]+)', sep), function(c)
        fields[#fields + 1] = c
    end)

    return fields
end
