local LANGUAGE_NAMES = {
    ar = 'العربية', da = 'Dansk', de = 'Deutsch', en = 'English', es = 'Español',
    et = 'Eesti', fi = 'Suomi', fr = 'Français', is = 'Íslenska', it = 'Italiano',
    ja = '日本語', lt = 'Lietuvių', nl = 'Nederlands', pt = 'Português',
    ['pt-br'] = 'Português (Brasil)', ro = 'Română', ru = 'Русский', sk = 'Slovenčina', th = 'ไทย',
    tr = 'Türkçe', ua = 'Українська', vn = 'Tiếng Việt',
}

local function languageName(code)
    return LANGUAGE_NAMES[code] or code
end

---Opens the per-player language selector. The chosen language belongs to the
---FiveM client and is saved by kora_lib in KVP storage, not PlayerData.
local selectorOpen = false

function Core.locales.openSelector()
    if selectorOpen then return end
    selectorOpen = true
    local current = Kora.locale.getLanguage()
    local items = {}
    for _, code in ipairs(Kora.locale.getLanguages()) do
        items[#items + 1] = {
            id = code,
            label = languageName(code),
            description = code == current and Kora.lang('Language.current') or code,
            icon = 'Languages',
        }
    end

    local ok, result = pcall(Kora.nui.openMenu, items, Kora.lang('Language.title'))
    selectorOpen = false
    if not ok then return end
    if not result or result.cancelled or not result.selectedId then return end

    local set, err = Kora.locale.setLanguage(result.selectedId)
    if set then
        Kora.notify.send({
            title = Kora.lang('Language.title'),
            message = Kora.lang('Language.changed', languageName(result.selectedId)),
            type = 'success',
        })
    else
        Kora.notify.send({ title = Kora.lang('Language.title'), message = err, type = 'error' })
    end
end

RegisterCommand('language', function()
    Core.locales.openSelector()
end, false)

RegisterCommand('+language', function()
    Core.locales.openSelector()
end, false)
RegisterCommand('-language', function() end, false)

RegisterKeyMapping('+language', Kora.lang('Language.open_selector'), 'keyboard', (Config.locales and Config.locales.defaultKey) or '')
