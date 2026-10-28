-- Compatibility locale object for resources that still include
-- '@qb-core/shared/locale.lua'. Unlike upstream's one-global-language version,
-- this retains every loaded phrase table and resolves against kora_lib's local
-- client KVP preference at lookup time.
Locale = {}
Locale.__index = Locale

local function currentLanguage()
    if not IsDuplicityVersion or not IsDuplicityVersion() then
        local ok, language = pcall(function() return exports.kora_lib:locale_getLanguage() end)
        if ok and type(language) == 'string' then return language end
    end
    return GetConvar('qb_locale', 'en')
end

function Locale:new(props)
    local self = setmetatable({}, Locale)
    self.locales = {}
    self.warnOnMissing = (props and props.warnOnMissing) or false
    self.resource = GetCurrentResourceName()

    if props and type(props.phrases) == 'table' then
        self:addLocale((props.currentLocale or 'en'), props.phrases)
    end
    return self
end

function Locale:addLocale(language, phrases)
    assert(type(language) == 'string' and language ~= '', 'Locale language must be a non-empty string.')
    assert(type(phrases) == 'table', 'Locale phrases must be a table.')
    self.locales[language] = phrases
end

function Locale:getPhrase(path, language)
    local result = self.locales[language or currentLanguage()] or self.locales.en
    for key in path:gmatch('[^%.]+') do
        if type(result) ~= 'table' then return nil end
        result = result[key]
    end
    return result
end

function Locale:interpPhrase(phrase, subs)
    if type(phrase) ~= 'string' then return phrase end
    for key, val in pairs(subs or {}) do
        phrase = phrase:gsub('%%{' .. key .. '}', tostring(val))
    end
    return phrase
end

function Locale:t(path, subs)
    local translated = self:getPhrase(path)
    if translated ~= nil then return self:interpPhrase(translated, subs) end
    if self.warnOnMissing then print(('[LOCALE] Missing key: %s'):format(path)) end
    return path
end

-- A compact, serializable reference for server->client UI. The receiving
-- kora_core client resolves it using the recipient's language, not the server's
-- default. Keep ordinary `t()` as a string for command/help/database callers.
function Locale:forPlayer(path, subs)
    return {
        __qb_locale = true,
        resource = self.resource,
        key = path,
        substitutions = subs,
    }
end
