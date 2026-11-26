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

local function register()
    Core.inventory.createUseable('id_card', showIdCard)
    Core.inventory.createUseable('driver_license', showDriverLicense)
end

register()

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == providerName() then
        register()
    end
end)
