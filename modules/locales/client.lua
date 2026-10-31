local LANGUAGE_NAMES = {
    ar = 'العربية', da = 'Dansk', de = 'Deutsch', en = 'English', es = 'Español',
    et = 'Eesti', fi = 'Suomi', fr = 'Français', is = 'Íslenska', it = 'Italiano',
    ja = '日本語', lt = 'Lietuvių', nl = 'Nederlands', pt = 'Português',
    ['pt-br'] = 'Português (Brasil)', ro = 'Română', sk = 'Slovenčina', th = 'ไทย',
    tr = 'Türkçe', vn = 'Tiếng Việt',
}

local function languageName(code)
    return LANGUAGE_NAMES[code] or code
end

---Opens the per-player language selector. The chosen language belongs to the
---FiveM client and is saved by kora_lib in KVP storage, not PlayerData.
function Core.locales.openSelector()
    local current = Kora.locale.getLanguage()
    local items = {}
    for _, code in ipairs(Kora.locale.getLanguages()) do
        items[#items + 1] = {
            id = code,
            label = languageName(code),
            description = code == current and 'Current language' or code,
            icon = 'Languages',
        }
    end

    -- kora_lib resolves NUI requests before returning them across a resource
    -- export boundary; kora_core therefore receives the result directly here.
    local result = Kora.nui.openMenu(items, 'Language')
    if not result or result.cancelled or not result.selectedId then return end

    local ok, err = Kora.locale.setLanguage(result.selectedId)
    if ok then
        Kora.notify.send({ title = 'Language', message = ('Language set to %s.'):format(languageName(result.selectedId)), type = 'success' })
    else
        Kora.notify.send({ title = 'Language', message = err, type = 'error' })
    end
end

RegisterCommand('language', function()
    Core.locales.openSelector()
end, false)

RegisterKeyMapping('language', 'Open language selector', 'keyboard', '')
