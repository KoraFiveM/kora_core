-- Core.multichar (client realm) -- a MINIMAL default flow so a bare server (no
-- character-select UI) still spawns the player. It requests the character list
-- and auto-selects slot 1, creating a default character if none exist. A real
-- UI resource overrides this by handling the same events itself and calling the
-- exports below instead.

local selecting = false

---Ask the server for this player's characters.
function Core.multichar.request()
    TriggerServerEvent('qbcore:server:requestCharacters')
end

---Select an existing character by citizenid.
---@param citizenid string
function Core.multichar.select(citizenid)
    TriggerServerEvent('qbcore:server:selectCharacter', citizenid)
end

---Create a new character.
---@param charinfo table
---@param cid integer|nil
function Core.multichar.create(charinfo, cid)
    TriggerServerEvent('qbcore:server:createCharacter', charinfo, cid)
end

-- Default auto-flow: if no UI resource claims the slot within a moment, pick or
-- create slot 1. A UI resource sets `_G.__qbcoreCharSelectUI = true` to suppress
-- this.
RegisterNetEvent('qbcore:client:receiveCharacters', function(characters)
    if _G.__qbcoreCharSelectUI or selecting then return end
    selecting = true
    if characters and characters[1] then
        Core.multichar.select(characters[1].citizenid)
    else
        Core.multichar.create({
            firstname = 'John', lastname = 'Doe', birthdate = '1990-01-01',
            gender = 0, nationality = 'USA', phone = tostring(math.random(1000000, 9999999)),
        }, 1)
    end
end)

RegisterNetEvent('qbcore:client:characterSelected', function(ok, err)
    if not ok then
        print(('^1[qbcore:multichar]^7 character select failed: %s'):format(tostring(err)))
        selecting = false
    end
end)

-- Kick off the default flow shortly after load unless a UI took over.
CreateThread(function()
    Wait(500)
    if not _G.__qbcoreCharSelectUI then
        Core.multichar.request()
    end
end)
