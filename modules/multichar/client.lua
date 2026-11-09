local selecting = false
local uiClaimed = false

---A character-select UI resource calls this (via `exports.kora_core:claimUI()` --
---qbcore's flat exports are named after the function alone, not
---`<module>_<fn>`; see build/finalise.lua) to suppress the default
---auto-select/auto-create flow below. Must be called
---before ~500ms after THIS resource's own scripts start, or the default flow
---may already have fired -- see the kick-off thread at the bottom of this file.
---
---An export rather than a `_G` flag: each resource has its own Lua VM, so only a
---cross-resource call reaches this script.
function Core.multichar.claimUI()
    uiClaimed = true
end

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

RegisterNetEvent('qbcore:client:receiveCharacters', function(characters)
    if uiClaimed or selecting then return end
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
        print(('^1[kora_core:multichar]^7 character select failed: %s'):format(tostring(err)))
        selecting = false
    end
end)

CreateThread(function()
    Wait(500)
    if not uiClaimed then
        Core.multichar.request()
    end
end)
