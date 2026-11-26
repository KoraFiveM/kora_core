-- Stock qb-inventory parity: id_card / driver_license show holder details in
-- chat to everyone within SHOW_RADIUS. Registered through createUseable so the
-- gateway forwards them to kora_inventory when it is the provider.
-- A later resource (e.g. an id-card NUI) may overwrite these handlers.

local SHOW_RADIUS = 3.0

local ID_CARD_TEMPLATE =
    '<div class="chat-message advert" style="background: linear-gradient(to right, rgba(5, 5, 5, 0.6), #74807c); display: flex;"><div style="margin-right: 10px;"><i class="far fa-id-card" style="height: 100%;"></i><strong> {0}</strong><br> <strong>Civ ID:</strong> {1} <br><strong>First Name:</strong> {2} <br><strong>Last Name:</strong> {3} <br><strong>Birthdate:</strong> {4} <br><strong>Gender:</strong> {5} <br><strong>Nationality:</strong> {6}</div></div>'

local DRIVER_LICENSE_TEMPLATE =
    '<div class="chat-message advert" style="background: linear-gradient(to right, rgba(5, 5, 5, 0.6), #657175); display: flex;"><div style="margin-right: 10px;"><i class="far fa-id-card" style="height: 100%;"></i><strong> {0}</strong><br> <strong>First Name:</strong> {1} <br><strong>Last Name:</strong> {2} <br><strong>Birth Date:</strong> {3} <br><strong>Licenses:</strong> {4}</div></div>'

local function providerName()
    return (Config.inventory and Config.inventory.provider) or 'kora_inventory'
end

---@param item table|nil
---@return table
local function rawInfo(item)
    if type(item) ~= 'table' then return {} end
    local info = item.info or item.metadata
    return type(info) == 'table' and info or {}
end

---Prefer item metadata; fill gaps from the holder's live PlayerData (starters
---sometimes arrive with an empty info table).
---@param src integer
---@param item table|nil
---@return table
local function cardInfo(src, item)
    local info = {}
    for key, value in pairs(rawInfo(item)) do
        info[key] = value
    end

    local player = CoreInternal.player.handle(src)
    if not player then return info end

    local charinfo = player.PlayerData.charinfo or {}
    if info.citizenid == nil then info.citizenid = player.PlayerData.citizenid end
    if info.firstname == nil then info.firstname = charinfo.firstname end
    if info.lastname == nil then info.lastname = charinfo.lastname end
    if info.birthdate == nil then info.birthdate = charinfo.birthdate end
    if info.gender == nil then info.gender = charinfo.gender end
    if info.nationality == nil then info.nationality = charinfo.nationality end
    return info
end

---@param a vector3|{x:number,y:number,z:number}
---@param b vector3|{x:number,y:number,z:number}
---@return number
local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---@param src integer
---@return integer[]
local function nearbyPlayers(src)
    local origin = GetEntityCoords(GetPlayerPed(src))
    local out = {}
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if target and distance(origin, GetEntityCoords(GetPlayerPed(target))) < SHOW_RADIUS then
            out[#out + 1] = target
        end
    end
    return out
end

---@param src integer
---@param item table
local function showIdCard(src, item)
    local info = cardInfo(src, item)
    local gender = info.gender == 0 and 'Male' or 'Female'
    local payload = {
        template = ID_CARD_TEMPLATE,
        args = {
            'ID Card',
            info.citizenid,
            info.firstname,
            info.lastname,
            info.birthdate,
            gender,
            info.nationality,
        },
    }
    for _, target in ipairs(nearbyPlayers(src)) do
        TriggerClientEvent('chat:addMessage', target, payload)
    end
end

---@param src integer
---@param item table
local function showDriverLicense(src, item)
    local info = cardInfo(src, item)
    local payload = {
        template = DRIVER_LICENSE_TEMPLATE,
        args = {
            'Drivers License',
            info.firstname,
            info.lastname,
            info.birthdate,
            info.type,
        },
    }
    for _, target in ipairs(nearbyPlayers(src)) do
        TriggerClientEvent('chat:addMessage', target, payload)
    end
end

---kora_inventory only consults its OWN useables table. A registration that
---lands on kora_core's legacy table while the provider is down is invisible
---once the provider starts, so provider registration is what counts as success.
---@return boolean registeredOnProvider
local function register()
    local provider = providerName()
    if GetResourceState(provider) ~= 'started' then
        -- Unit tests / staged fallback only. Ignored by kora_inventory at runtime.
        if Config.inventory and Config.inventory.allowLegacyFallback then
            Core.inventory.createUseable('id_card', showIdCard)
            Core.inventory.createUseable('driver_license', showDriverLicense)
        end
        return false
    end

    -- Prefer the documented native export (powers the NUI Use button).
    -- Fall back through the gateway so ownership still hops correctly.
    local ok, err = pcall(function()
        exports[provider]:createUseable('id_card', showIdCard)
        exports[provider]:createUseable('driver_license', showDriverLicense)
    end)
    if not ok then
        ok, err = pcall(function()
            Core.inventory.createUseable('id_card', showIdCard)
            Core.inventory.createUseable('driver_license', showDriverLicense)
        end)
    end
    if not ok then
        Kora.logging.warn('inventory.identity_cards_register_failed', 'Stock identity card useables failed to register', {
            provider = provider,
            error = tostring(err),
        })
        return false
    end
    return true
end

register()

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= providerName() then return end
    -- Defer one tick so the provider's export table is fully published.
    SetTimeout(0, function()
        register()
    end)
end)

-- Fresh boot safety net: kora_core always starts before kora_inventory, so the
-- first register() above cannot hit the provider. Retry briefly after boot in
-- case onResourceStart races the export publish.
do
    local attempts = 0
    local function retry()
        attempts = attempts + 1
        if register() or attempts >= 50 then return end
        SetTimeout(100, retry)
    end
    SetTimeout(0, retry)
end
