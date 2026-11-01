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

local function setNested(tree, key, value)
    local parts = {}
    for part in key:gmatch('[^%.]+') do parts[#parts + 1] = part end
    if #parts == 0 then return end
    for i = 1, #parts - 1 do
        local nextNode = tree[parts[i]]
        if nextNode == nil then
            nextNode = {}
            tree[parts[i]] = nextNode
        end
        if type(nextNode) ~= 'table' then return end
        tree = nextNode
    end
    tree[parts[#parts]] = value
end

function Locale:new(props)
    local self = setmetatable({}, Locale)
    self.locales = {}
    self.phrases = {}
    self.baseLanguage = (props and props.currentLocale) or 'en'
    self.warnOnMissing = not (props and type(props.warnOnMissing) == 'boolean') or props.warnOnMissing
    self.resource = GetCurrentResourceName()
    self.fallback = props and type(props.fallbackLang) == 'table' and Locale:new({
        warnOnMissing = false,
        phrases = props.fallbackLang.phrases,
    }) or false

    if props and type(props.phrases) == 'table' then
        self:extend(props.phrases)
    end
    return self
end

function Locale:addLocale(language, phrases)
    assert(type(language) == 'string' and language ~= '', 'Locale language must be a non-empty string.')
    assert(type(phrases) == 'table', 'Locale phrases must be a table.')
    self.locales[language] = phrases
    if language == self.baseLanguage then
        self.phrases = {}
        self:extend(phrases)
    end
end

function Locale:extend(phrases, prefix)
    local tree = self.locales[self.baseLanguage]
    if not tree then
        tree = {}
        self.locales[self.baseLanguage] = tree
    end
    for key, phrase in pairs(phrases) do
        local prefixKey = prefix and ('%s.%s'):format(prefix, key) or tostring(key)
        if type(phrase) == 'table' then
            self:extend(phrase, prefixKey)
        else
            self.phrases[prefixKey] = phrase
            setNested(tree, prefixKey, phrase)
        end
    end
end

function Locale:clear()
    self.phrases = {}
    self.locales[self.baseLanguage] = {}
end

function Locale:replace(phrases)
    self:clear()
    self:extend(phrases or {})
end

function Locale:locale(newLocale)
    if newLocale then self.currentLocale = newLocale end
    return self.currentLocale
end

function Locale:has(key)
    return type(self:getPhrase(key)) == 'string'
end

function Locale:delete(target, prefix)
    if type(target) == 'string' then
        self.phrases[target] = nil
        setNested(self.locales[self.baseLanguage] or {}, target, nil)
        return
    end
    for key, phrase in pairs(target) do
        local prefixKey = prefix and (prefix .. '.' .. key) or tostring(key)
        if type(phrase) == 'table' then
            self:delete(phrase, prefixKey)
        else
            self:delete(prefixKey)
        end
    end
end

function Locale:getPhrase(path, language)
    local result = self.locales[language or self.currentLocale or currentLanguage()] or self.locales.en
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
    if self.fallback then return self.fallback:t(path, subs) end
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
