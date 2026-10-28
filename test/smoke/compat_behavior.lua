-- Compat shape test -- asserts every documented legacy field of the QBCore
-- object exists and is callable, and that the per-player Player.Functions.*
-- table is complete. This is what keeps compat honest: an internal rename that
-- drops a legacy method fails HERE at CI, not in someone's production server.

local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua')
local handle = mocks.install()

dofile('config.lua')
dofile('shared/items.lua'); dofile('shared/jobs.lua'); dofile('shared/gangs.lua')
dofile('shared/vehicles.lua'); dofile('shared/weapons.lua'); dofile('shared/locations.lua')
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/server.lua')
dofile('modules/player/shared.lua')
dofile('modules/replication/server.lua')
dofile('modules/persistence/server.lua')
dofile('modules/player/server.lua')
dofile('modules/money/server.lua')
dofile('modules/jobs/server.lua')
dofile('modules/metadata/server.lua')
dofile('modules/inventory/shared.lua'); dofile('modules/inventory/server.lua')
dofile('modules/inventory/gateway.lua')
dofile('modules/multichar/server.lua')
dofile('modules/permissions/server.lua')
dofile('modules/commands/server.lua')
dofile('modules/logging/server.lua')
dofile('compat/shared/coreobject.lua')
dofile('compat/server/qb-core.lua')
dofile('compat/server/qb-core-events.lua')

local function player(src)
    local data = CoreInternal.player.freshData('PARITY' .. src, 'license:parity' .. src, 1,
        { firstname = 'Compat', lastname = 'Player' })
    h.assertTrue(Core.player.login(src, data.citizenid, data))
    return QBCore.Functions.GetPlayer(src), CoreInternal.player.handle(src)
end

h.test('online built-ins accept colon, direct dot, and Functions calls', function()
    local p = player(71)
    h.assertTrue(p:SetMetaData('bloodtype', 'AB-'))
    h.assertEqual(p:GetMetaData('bloodtype'), 'AB-')
    h.assertTrue(p.SetMetaData('bloodtype', 'A+'))
    h.assertEqual(p.Functions.GetMetaData('bloodtype'), 'A+')
    h.assertTrue(p:SetJob('police', 1))
    h.assertEqual(p.PlayerData.job.grade.level, 1)
    local copy = { PlayerData = Core.util.deepClone(p.PlayerData), Functions = p.Functions }
    h.assertTrue(p.SetMetaData(copy, 'bloodtype', 'O-'), 'CFX copies of the receiver retain colon semantics')
    h.assertEqual(p.Functions.GetMetaData('bloodtype'), 'O-')
    local before = p.Functions.GetMoney('cash')
    h.assertTrue(p:AddMoney('cash', 5, 'parity'))
    h.assertEqual(p:GetMoney('cash'), before + 5)
end)

h.test('offline built-ins support colon and dot while custom handlers stay unbound', function()
    local p = Core.compat.buildOfflinePlayer(CoreInternal.player.freshData('OFFLINE', 'license:o', 1, {}))
    h.assertTrue(p:SetMetaData('bloodtype', 'AB-'))
    h.assertEqual(p:GetMetaData('bloodtype'), 'AB-')
    h.assertTrue(p.SetMetaData('bloodtype', 'A+'))
    h.assertEqual(p.Functions.GetMetaData('bloodtype'), 'A+')
    local custom = function(value) return value end
    h.assertTrue(p:AddMethod('Echo', custom))
    h.assertEqual(p.Functions.Echo('hello'), 'hello')
    h.assertEqual(p:Echo(), p, 'custom AddMethod callbacks keep upstream argument binding')
end)

h.test('legacy metadata clamps hunger and thirst without changing other fields', function()
    local p = player(72)
    p.Functions.SetMetaData('hunger', 150)
    p:SetMetaData('thirst', -20)
    p:SetMetaData('stress', 150)
    h.assertEqual(p:GetMetaData('hunger'), 100)
    h.assertEqual(p:GetMetaData('thirst'), 0)
    h.assertEqual(p:GetMetaData('stress'), 150)
end)

h.test('UpdatePlayerData commits direct edits through persistence and replication', function()
    local p, native = player(73)
    Core.persistence.saveNow(native)
    handle.drainTimeouts()
    local changed, allData
    AddEventHandler('QBCore:Server:OnPlayerUpdated', function(src, key, value)
        if src == 73 then changed = { key, value } end
    end)
    AddEventHandler('QBCore:Player:SetPlayerData', function(data)
        if data.source == 73 then allData = data end
    end)
    p.PlayerData.charinfo.firstname = 'Changed'
    p.PlayerData.job.grade.level = 2
    h.assertEqual(native.PlayerData.charinfo.firstname, 'Compat', 'view edits cannot bypass the funnel')
    h.assertTrue(p.Functions.UpdatePlayerData())
    h.assertEqual(native.PlayerData.charinfo.firstname, 'Changed')
    h.assertTrue(native._dirty.charinfo)
    h.assertEqual(native.PlayerData.job.grade.level, 3)
    h.assertEqual(changed[1], 'all')
    h.assertEqual(changed[2].job.grade.level, 2)
    h.assertEqual(allData.charinfo.firstname, 'Changed')
    handle.drainTimeouts()
    local delta = handle.lastClient('qbcore:rep:delta')
    h.assertEqual(delta.target, 73)
    local update = handle.lastClient('QBCore:Client:OnPlayerUpdated')
    h.assertEqual(update.args[1], 'all')
    h.assertEqual(update.args[2].charinfo.firstname, 'Changed')
end)

h.test('keyed UpdateClient preserves false and publishes after the delta', function()
    local p = player(74)
    handle.drainTimeouts()
    h.assertTrue(p:UpdateClient('optin', false))
    h.assertEqual(Core.player.getPlayerData(74, { 'optin' }), false)
    handle.drainTimeouts()
    local update = handle.lastClient('QBCore:Client:OnPlayerUpdated')
    h.assertEqual(update.args[1], 'optin')
    h.assertEqual(update.args[2], false)
    local deltaIndex, updateIndex
    for index, event in ipairs(handle.clientEvents) do
        if event.target == 74 and event.name == 'qbcore:rep:delta' then deltaIndex = index end
        if event.target == 74 and event.name == 'QBCore:Client:OnPlayerUpdated' then updateIndex = index end
    end
    h.assertTrue(deltaIndex < updateIndex)
end)

h.test('legacy edits retain transaction fences, field ownership and immutable identity', function()
    local p, native = player(75)
    local previous = Core.persistence._canWriteColumn
    Core.persistence._canWriteColumn = function(_, column) return column ~= 'money' end
    local before = native.PlayerData.money.bank
    p.PlayerData.money.bank = before + 1000
    local ok, reason = p:UpdateClient('money')
    h.assertFalse(ok)
    h.assertEqual(reason, 'player data is busy')
    h.assertEqual(native.PlayerData.money.bank, before)
    h.assertEqual(p.PlayerData.money.bank, before)
    Core.persistence._canWriteColumn = previous
    p.PlayerData.citizenid = 'HIJACK'
    h.assertFalse(p:UpdateClient('citizenid'))
    h.assertEqual(native.PlayerData.citizenid, 'PARITY75')
    h.assertFalse(p:SetPlayerData('license', 'license:other'))
    local invoking = GetInvokingResource
    GetInvokingResource = function() return 'field_owner' end
    h.assertTrue(Core.player.registerPlayerDataField('parity_owned', function() return { value = 1 } end))
    GetInvokingResource = function() return 'other_resource' end
    p.PlayerData.parity_owned.value = 2
    h.assertFalse(p:UpdateClient('parity_owned'))
    h.assertEqual(native.PlayerData.parity_owned.value, 1)
    GetInvokingResource = invoking
end)

h.test('legacy money root replacement cannot bypass physical cash authority', function()
    local p, native = player(76)
    local physical = Core.money.isPhysicalCash
    Core.money.isPhysicalCash = function(account) return account == 'cash' end
    local before = native.PlayerData.money.cash
    p.PlayerData.money.cash = before + 100
    h.assertFalse(p:UpdatePlayerData())
    h.assertEqual(native.PlayerData.money.cash, before)
    h.assertFalse(p:SetPlayerData('money', { cash = before + 100, bank = 0 }))
    Core.money.isPhysicalCash = physical
end)

h.test('all legacy role writers translate grade levels without mutating inputs', function()
    local p, native = player(77)
    local job = { name = 'police', label = 'Police', grade = { level = 1, name = 'Officer' }, onduty = true }
    h.assertTrue(p:SetPlayerData('job', job))
    h.assertEqual(job.grade.level, 1)
    h.assertEqual(native.PlayerData.job.grade.level, 2)
    h.assertEqual(p.PlayerData.job.grade.level, 1)
    h.assertTrue(p:SetJobData('grade', { level = 2, name = 'Sergeant' }))
    h.assertEqual(native.PlayerData.job.grade.level, 3)
    h.assertEqual(p.PlayerData.job.grade.level, 2)
    h.assertTrue(p:SetGangData('grade', { level = 1, name = 'Member' }))
    h.assertEqual(native.PlayerData.gang.grade.level, 2)
    h.assertEqual(p.PlayerData.gang.grade.level, 1)
    local capturedJob = p.PlayerData.job
    Core.player.setPath(77, { 'job', 'grade', 'level' }, 4)
    h.assertEqual(p.PlayerData.job.grade.level, 3)
    h.assertEqual(capturedJob.grade.level, 3, 'nested role changes preserve captured legacy table references')
end)

h.test('shared add/update/bulk events keep legacy grades and leave caller tables intact', function()
    local function role()
        return { label = 'Parity', defaultDuty = false, grades = {
            ['0'] = { name = 'Starter', payment = 10 }, ['1'] = { name = 'Senior', payment = 20 },
        } }
    end
    local job = role()
    h.assertTrue(QBCore.Functions.AddJob('parity_job', job))
    h.assertTrue(job.grades['0'] ~= nil and job.grades[1] == nil)
    local event = handle.lastClient('QBCore:Client:OnSharedUpdate')
    h.assertEqual(event.args[3].grades['0'].name, 'Starter')
    h.assertEqual(event.args[3].grades[1], nil)
    local updated = role(); updated.grades['0'].name = 'Updated'
    h.assertTrue(QBCore.Functions.UpdateJob('parity_job', updated))
    event = handle.lastClient('QBCore:Client:OnSharedUpdate')
    h.assertEqual(event.args[3].grades['0'].name, 'Updated')
    h.assertTrue(updated.grades['0'] ~= nil)
    local gangs = { parity_a = role(), parity_b = role() }
    h.assertTrue(QBCore.Functions.AddGangs(gangs))
    event = handle.lastClient('QBCore:Client:OnSharedUpdateMultiple')
    h.assertTrue(event.args[2].parity_a.grades['0'] ~= nil)
    h.assertTrue(gangs.parity_a.grades['0'] ~= nil)
end)

h.test('CanUseItem returns registered records, including native registrations, or nil', function()
    h.assertEqual(QBCore.Functions.CanUseItem('water_bottle'), nil)
    local calls = 0
    local callback = function(src) calls = calls + src end
    QBCore.Functions.CreateUseableItem('water_bottle', { callback = callback })
    local useable = QBCore.Functions.CanUseItem('water_bottle')
    h.assertEqual(useable.func, callback)
    h.assertTrue(type(useable.resource) == 'string')
    useable.func(3, {})
    h.assertEqual(calls, 3)
    Core.inventory.createUseable('native_item', callback)
    h.assertEqual(QBCore.Functions.CanUseItem('native_item').func, callback)
    h.assertEqual(QBCore.Functions.CanUseItem('missing_item'), nil)
end)

h.test('CanUseItem queries the active inventory authority', function()
    local previous = exports.kora_inventory
    local callback = function() end
    exports.kora_inventory = { getUseable = function(_, name)
        if name == 'provider_item' then return { func = callback, resource = 'provider_owner' } end
    end }
    handle.resourceStates.kora_inventory = 'started'
    h.assertEqual(QBCore.Functions.CanUseItem('provider_item').func, callback)
    h.assertEqual(QBCore.Functions.CanUseItem('water_bottle'), nil, 'no fallback to stale core registrations')
    handle.resourceStates.kora_inventory = nil
    exports.kora_inventory = previous
end)

h.test('legacy setters emit current legacy-shaped player-update notifications', function()
    local p = player(78)
    local events = {}
    AddEventHandler('QBCore:Server:OnPlayerUpdated', function(src, key, value)
        if src == 78 then events[key] = value end
    end)
    p:SetMetaData('bloodtype', 'B-')
    h.assertEqual(events.metadata.bloodtype, 'B-')
    p:SetPlayerData('optin', false)
    h.assertEqual(events.optin, false)
    p:SetJobData('grade', { level = 1 })
    h.assertEqual(events.job.grade.level, 1)
end)

h.test('usable registration preserves the external owner through the provider hop', function()
    local previous, invoking = exports.kora_inventory, GetInvokingResource
    local registered
    exports.kora_inventory = {
        createUseable = function(_, name, callback, owner)
            registered = { name = name, func = callback, resource = owner }
        end,
        getUseable = function() return registered end,
    }
    GetInvokingResource = function() return 'legacy_shop' end
    handle.resourceStates.kora_inventory = 'started'
    local callback = function() end
    QBCore.Functions.CreateUseableItem('provider_registered', callback)
    h.assertEqual(registered.resource, 'legacy_shop')
    h.assertEqual(QBCore.Functions.CanUseItem('provider_registered').func, callback)
    handle.resourceStates.kora_inventory = nil
    exports.kora_inventory, GetInvokingResource = previous, invoking
end)

h.test('role updates use one notification source and explicit refreshes still notify', function()
    local p = player(79)
    handle.drainTimeouts()
    local function countUpdates()
        local count = 0
        for _, event in ipairs(handle.clientEvents) do
            if event.target == 79 and event.name == 'QBCore:Client:OnPlayerUpdated' then count = count + 1 end
        end
        return count
    end
    local before = countUpdates()
    h.assertTrue(p:SetJobData('grade', { level = 1 }))
    handle.drainTimeouts()
    h.assertEqual(countUpdates(), before, 'the queued role delta already derives the client notification')
    h.assertTrue(p:UpdateClient('job'))
    handle.drainTimeouts()
    h.assertEqual(countUpdates(), before + 1, 'an explicit refresh without a delta must still notify')
    before = countUpdates()
    p.PlayerData.charinfo.firstname = 'Saved'
    h.assertTrue(p:Save())
    handle.drainTimeouts()
    h.assertEqual(countUpdates(), before, 'saving does not invent an extra update notification')
end)

h.test('stale player methods cannot write after logout or source reuse', function()
    local p = player(80)
    h.assertTrue(Core.player.logout(80))
    h.assertFalse(p:SetPlayerData('money', { bank = 1 }))
    local data = CoreInternal.player.freshData('REUSED80', 'license:reuse', 1, {})
    h.assertTrue(Core.player.login(80, data.citizenid, data))
    local before = Core.player.getPlayerData(80)
    h.assertFalse(p:UpdateClient('money', { bank = 1 }))
    h.assertFalse(p.Functions.SetPlayerData('money', { bank = 1 }))
    h.assertFalse(p:SetMetaData('bloodtype', 'stale'))
    h.assertEqual(Core.player.getPlayerData(80, { 'money', 'bank' }), before.money.bank)
    h.assertEqual(Core.player.getPlayerData(80, { 'metadata', 'bloodtype' }), before.metadata.bloodtype)
end)

h.test('legacy job reputation aliases update the current job through the funnel', function()
    local p, native = player(81)
    h.assertTrue(p:SetJob('police', 0))
    h.assertTrue(p:SetMetaData('jobrep', { police = 7, ambulance = 11 }))
    h.assertTrue(p:SetMetaData('rep', { police = 500 }))
    Core.persistence.saveNow(native)
    local original = native.PlayerData.metadata.jobrep
    local updates = 0
    AddEventHandler('QBCore:Server:OnPlayerUpdated', function(src, key, value)
        if src == 81 and key == 'all' then
            updates = updates + 1
            h.assertEqual(value.metadata.jobrep[value.job.name], native.PlayerData.metadata.jobrep[value.job.name])
        end
    end)
    h.assertEqual(p.Functions.AddJobReputation('3'), nil, 'upstream success has no return value')
    h.assertEqual(original.police, 7, 'do not mutate authority before entering the funnel')
    h.assertEqual(native.PlayerData.metadata.jobrep.police, 10)
    h.assertTrue(native._dirty.metadata)
    p:AddJobRep(-12)
    h.assertEqual(p.PlayerData.metadata.jobrep.police, -2, 'legacy job reputation has no zero clamp')
    h.assertTrue(p:SetJob('ambulance', 0))
    p.AddJobReputation(4)
    h.assertEqual(native.PlayerData.metadata.jobrep.ambulance, 15, 'resolve the current job on each call')
    h.assertEqual(native.PlayerData.metadata.rep.police, 500, 'generic reputation uses a different map')
    h.assertEqual(updates, 3)
    p:AddJobRep('invalid')
    h.assertEqual(updates, 3)
end)

h.test('job reputation respects metadata transaction fences and stale player handles', function()
    local p, native = player(82)
    local previous = Core.persistence._canWriteColumn
    Core.persistence._canWriteColumn = function(_, column) return column ~= 'metadata' end
    local ok, reason = p:AddJobRep(10)
    Core.persistence._canWriteColumn = previous
    h.assertFalse(ok)
    h.assertEqual(reason, 'player data is busy')
    h.assertEqual(native.PlayerData.metadata.jobrep, nil)
    h.assertEqual(p.PlayerData.metadata.jobrep, nil)
    h.assertTrue(Core.player.logout(82))
    h.assertFalse(p.Functions.AddJobReputation(5))
end)

h.test('offline job reputation aliases initialize and preserve the legacy map', function()
    local p = Core.compat.buildOfflinePlayer(CoreInternal.player.freshData('REP_OFFLINE', 'license:rep', 1, {}))
    p:SetMetaData('rep', { unemployed = 100 })
    h.assertEqual(p:AddJobReputation('3'), nil)
    p.Functions.AddJobRep(-5)
    h.assertEqual(p.PlayerData.metadata.jobrep.unemployed, -2)
    h.assertTrue(p:SetJob('police', 0))
    p.AddJobRep(6)
    h.assertEqual(p.PlayerData.metadata.jobrep.police, 6)
    h.assertEqual(p.PlayerData.metadata.jobrep.unemployed, -2)
    h.assertEqual(p.PlayerData.metadata.rep.unemployed, 100)
end)

h.test('GetItemInSlot preserves online and offline slot lookup semantics', function()
    local p = player(83)
    local item = { name = 'water_bottle', amount = 2, slot = 3, info = { batch = 'legacy' } }
    h.assertTrue(Core.player.setPath(83, { 'items', 3 }, item))
    h.assertEqual(p.Functions.GetItemInSlot(3), p.Functions.GetItemBySlot(3))
    h.assertEqual(p:GetItemInSlot(3).info.batch, 'legacy')
    h.assertEqual(p.GetItemInSlot(4), nil)
    local offline = Core.compat.buildOfflinePlayer(CoreInternal.player.freshData('SLOT_OFFLINE', 'license:slot', 1, {}))
    offline:SetInventory({ [3] = item })
    h.assertEqual(offline.Functions.GetItemInSlot(3), offline.Functions.GetItemBySlot(3))
    h.assertEqual(offline:GetItemInSlot('3').amount, 2)
    h.assertEqual(offline.GetItemInSlot(4), nil)
end)

h.test('metadata and generic reputation reject fenced writes without mutation or notifications', function()
    local p, native = player(84)
    p:SetMetaData('rep', { crafting = 10 })
    Core.persistence.saveNow(native)
    handle.drainTimeouts()
    local original = native.PlayerData.metadata.rep
    local metadataEvents, updateEvents = 0, 0
    AddEventHandler('QBCore:Server:OnMetaDataChange', function(src)
        if src == 84 then metadataEvents = metadataEvents + 1 end
    end)
    AddEventHandler('QBCore:Server:OnPlayerUpdated', function(src)
        if src == 84 then updateEvents = updateEvents + 1 end
    end)
    local previous = Core.persistence._canWriteColumn
    Core.persistence._canWriteColumn = function(_, column) return column ~= 'metadata' end
    local setOK, setError = p:SetMetaData('bloodtype', 'LOCKED')
    local increment, incrementError = Core.metadata.incrementMetaData(84, 'stress', 5)
    local addOK, addError = p:AddRep('crafting', 3)
    local removeOK, removeError = p.Functions.RemoveRep('crafting', 4)
    Core.persistence._canWriteColumn = previous
    h.assertFalse(setOK)
    h.assertEqual(setError, 'player data is busy')
    h.assertEqual(increment, nil)
    h.assertEqual(incrementError, 'player data is busy')
    h.assertFalse(addOK)
    h.assertFalse(removeOK)
    h.assertEqual(addError, 'player data is busy')
    h.assertEqual(removeError, 'player data is busy')
    h.assertEqual(native.PlayerData.metadata.bloodtype, 'O+')
    h.assertEqual(native.PlayerData.metadata.stress, 0)
    h.assertEqual(native.PlayerData.metadata.rep, original)
    h.assertEqual(original.crafting, 10)
    h.assertEqual(p.PlayerData.metadata.rep.crafting, 10)
    h.assertFalse(native._dirty.metadata)
    h.assertEqual(metadataEvents, 0)
    h.assertEqual(updateEvents, 0)
    h.assertTrue(p:SetMetaData('bloodtype', 'A+'))
    h.assertEqual(Core.metadata.incrementMetaData(84, 'stress', 5), 5)
    h.assertEqual(p:AddRep('crafting', 3), nil)
    h.assertEqual(p:RemoveRep('crafting', 4), nil)
    h.assertEqual(native.PlayerData.metadata.rep.crafting, 9)
    h.assertEqual(original.crafting, 10, 'successful writes also replace rather than mutate the old map')
    h.assertEqual(metadataEvents, 4)
end)

h.test('required-field saves reject fences while ordinary partial saves stay compatible', function()
    local p, native = player(85)
    Core.player.setPath(85, { 'items', 1 }, { name = 'water_bottle', amount = 1, slot = 1, info = {} })
    local previous = Core.persistence._isColumnLocked
    Core.persistence._isColumnLocked = function(_, column) return column == 'inventory' end
    local ok, err = Core.player.savePlayer(85, 'items')
    local ordinary = Core.player.savePlayer(85)
    Core.persistence._isColumnLocked = previous
    h.assertFalse(ok)
    h.assertEqual(err, 'player data is busy')
    h.assertTrue(ordinary, 'existing native call may save other unfenced columns')
    h.assertTrue(native._dirty.inventory, 'fenced inventory remains dirty')
    h.assertFalse(Core.player.savePlayer(85, 'license'))
    h.assertTrue(Core.player.savePlayer(85, 'items'))
    h.assertFalse(native._dirty.inventory)
end)

h.test('offline factory evaluates nested defaults without retaining callable values', function()
    local scalar = QB.sql.scalar
    QB.sql.scalar = function() return nil end
    local p = QBCore.Player.CheckPlayerData(nil, {
        citizenid = 'GENERATED_DEFAULTS', license = 'license:defaults', cid = 1,
        charinfo = { firstname = 'Preserved' },
    })
    QB.sql.scalar = scalar
    local function serializable(value)
        h.assertTrue(type(value) ~= 'function', 'PlayerData must not retain default generators')
        if type(value) == 'table' then for _, child in pairs(value) do serializable(child) end end
    end
    serializable(p.PlayerData)
    h.assertEqual(p.PlayerData.charinfo.firstname, 'Preserved')
    h.assertEqual(type(p.PlayerData.metadata.fingerprint), 'string')
    h.assertEqual(type(p.PlayerData.metadata.phonedata.SerialNumber), 'string')
    h.assertEqual(type(QBCore.Config.Player.PlayerDefaults.metadata.fingerprint), 'function', 'factory leaves shared defaults intact')
end)

h.test('legacy offline save uses native mutable fields and refuses online or fenced characters', function()
    local p = player(86)
    h.assertFalse(QBCore.Player.SaveOffline(p.PlayerData), 'an offline snapshot cannot overwrite an online character')
    local offline = Core.compat.buildOfflinePlayer(CoreInternal.player.freshData('OFFLINE_SAVE', 'license:save', 1, {}))
    offline:SetJob('police', 0)
    local oldUpdate, oldBusy = QB.sql.update, Core.persistence._hasColumnOperation
    local statement, params
    QB.sql.update = function(sql, values) statement, params = sql, values; return 1 end
    h.assertTrue(offline:Save())
    h.assertFalse(statement:find('`license` =', 1, true))
    h.assertFalse(statement:find('`cid` =', 1, true))
    h.assertEqual(json.decode(params[4]).grade.level, 1, 'save translates the job into native grade storage')
    Core.persistence._hasColumnOperation = function() return true end
    local ok, err = offline:Save()
    Core.persistence._hasColumnOperation, QB.sql.update = oldBusy, oldUpdate
    h.assertFalse(ok)
    h.assertEqual(err, 'player data is busy')
end)

h.test('first offline save inserts plainly and identity collisions never overwrite', function()
    local scalar = QB.sql.scalar
    QB.sql.scalar = function() return nil end
    local p = QBCore.Player.CheckPlayerData(nil, { citizenid = 'NEW_OFFLINE', license = 'license:new', cid = 1 })
    QB.sql.scalar = scalar
    local oldUpdate, oldSingle, oldExecute = QB.sql.update, QB.sql.single, QB.sql.execute
    local inserted
    QB.sql.update = function() return 0 end
    QB.sql.single = function() return nil end
    QB.sql.execute = function(sql) inserted = sql; return { affectedRows = 1 } end
    h.assertTrue(p:Save())
    h.assertTrue(inserted:find('INSERT INTO `players`', 1, true))
    h.assertFalse(inserted:find('ON DUPLICATE', 1, true), 'first-save collisions must fail, not update another row')
    QB.sql.execute = function() return nil, 'duplicate identity' end
    local ok, err = p:Save()
    QB.sql.update, QB.sql.single, QB.sql.execute = oldUpdate, oldSingle, oldExecute
    h.assertFalse(ok)
    h.assertEqual(err, 'duplicate identity')
end)

h.test('persisted native grades round-trip through offline loading and legacy login', function()
    local native = CoreInternal.player.freshData('GRADE_ROUNDTRIP', 'license:grade', 1, {})
    local offline = Core.compat.buildOfflinePlayer(native)
    offline:SetJob('police', 0)
    offline:SetGang('ballas', 1)
    local oldUpdate, oldSingle, oldScalar = QB.sql.update, QB.sql.single, QB.sql.scalar
    local oldIdentifiers, oldPlayerName = Core.identity.getIdentifiers, GetPlayerName
    GetPlayerName = function() return "Roundtrip Player" end
    local row = { citizenid = native.citizenid, license = native.license, cid = native.cid }
    QB.sql.scalar = function() return nil end
    QB.sql.update = function(_, values)
        row.name, row.money, row.charinfo, row.job, row.gang = values[1], values[2], values[3], values[4], values[5]
        row.position, row.metadata, row.inventory, row.phone = values[6], values[7], values[8], values[9]
        return 1
    end
    QB.sql.single = function(sql)
        if sql:find('SELECT * FROM `players`', 1, true) then return Core.util.deepClone(row) end
        return nil
    end
    h.assertTrue(offline:Save())
    h.assertEqual(json.decode(row.job).grade.level, 1)
    h.assertEqual(json.decode(row.gang).grade.level, 2)
    local loaded = QBCore.Functions.GetOfflinePlayerByCitizenId(native.citizenid)
    h.assertEqual(loaded.PlayerData.job.grade.level, 0)
    h.assertEqual(loaded.PlayerData.gang.grade.level, 1)
    h.assertTrue(loaded:Save())
    h.assertEqual(json.decode(row.job).grade.level, 1, 'repeated offline saves preserve native grades')
    h.assertEqual(json.decode(row.gang).grade.level, 2)
    Core.identity.getIdentifiers = function() return { license = native.license } end
    h.assertTrue(QBCore.Player.Login(87, native.citizenid))
    h.assertEqual(QBCore.Functions.GetPlayer(87).PlayerData.job.grade.level, 0)
    h.assertEqual(QBCore.Functions.GetPlayer(87).PlayerData.gang.grade.level, 1)
    h.assertEqual(CoreInternal.player.handle(87).PlayerData.job.grade.level, 1)
    h.assertEqual(CoreInternal.player.handle(87).PlayerData.gang.grade.level, 2)
    QB.sql.update, QB.sql.single, QB.sql.scalar = oldUpdate, oldSingle, oldScalar
    Core.identity.getIdentifiers, GetPlayerName = oldIdentifiers, oldPlayerName
end)

h.test('legacy command tuple arguments adapt without changing native or public contracts', function()
    local add = QB.commands.add
    local captured
    QB.commands.add = function(name, help, args, required, callback, options)
        captured = { args = args, required = required, callback = callback, options = options }
        return add(name, help, args, required, callback, options)
    end
    local tuple = { { 'id', 'ID of a person' }, { name = 'reason', help = 'Reason' } }
    local callback = function() end
    QBCore.Commands.Add('legacy_drivinglicense', 'License', tuple, true, callback, 'admin')
    QB.commands.add = add
    h.assertEqual(captured.args[1].name, 'id')
    h.assertEqual(captured.args[1].help, 'ID of a person')
    h.assertEqual(captured.args[2].name, 'reason')
    h.assertEqual(captured.required, true)
    h.assertEqual(captured.callback, callback)
    h.assertEqual(captured.options.permission, 'admin')
    h.assertEqual(tuple[1].name, nil, 'do not rewrite the caller table')
    h.assertEqual(QBCore.Commands.List.legacy_drivinglicense.params, tuple)
    h.assertEqual(QBCore.Commands.List.legacy_drivinglicense.callback, callback)
end)

h.test('legacy item additions reject names already exposed by the weapon registry', function()
    local original = Core.registry.getShared('weapons', 'weapon_pistol')
    local ok, reason = QBCore.Functions.AddItem('weapon_pistol', { label = 'Duplicate' })
    h.assertFalse(ok); h.assertEqual(reason, 'item_exists')
    ok, reason = QBCore.Functions.AddItems({ weapon_pistol = { label = 'Duplicate' }, new_batch_item = { label = 'New' } })
    h.assertFalse(ok); h.assertEqual(reason, 'item_exists')
    h.assertEqual(Core.registry.getShared('items', 'new_batch_item'), nil, 'duplicate preflight must not partially add the batch')
    h.assertEqual(Core.registry.getShared('weapons', 'weapon_pistol'), original)
end)

h.test('legacy item updates resolve the visible canonical definition and removal removes both', function()
    local name = 'weapon_legacy_mutation'
    h.assertTrue(Core.registry.registerShared('weapons', name, { name = name, label = 'Weapon', type = 'weapon' }))
    h.assertTrue(QBCore.Functions.UpdateItem(name, { name = name, label = 'Updated weapon', type = 'weapon' }))
    h.assertEqual(Core.registry.getShared('weapons', name).label, 'Updated weapon')
    h.assertEqual(Core.registry.getShared('items', name), nil)
    h.assertEqual(QBCore.Shared.Items[name].label, 'Updated weapon')
    h.assertTrue(Core.registry.registerShared('items', name, { name = name, label = 'Override', type = 'weapon' }))
    h.assertTrue(QBCore.Functions.UpdateItem(name, { name = name, label = 'Updated override', type = 'weapon' }))
    h.assertEqual(Core.registry.getShared('items', name).label, 'Updated override')
    h.assertEqual(Core.registry.getShared('weapons', name).label, 'Updated weapon')
    h.assertTrue(QBCore.Functions.RemoveItem(name))
    h.assertEqual(Core.registry.getShared('items', name), nil)
    h.assertEqual(Core.registry.getShared('weapons', name), nil)
    h.assertEqual(QBCore.Shared.Items[name], nil)
    local ok, reason = QBCore.Functions.UpdateItem(name, { name = name })
    h.assertFalse(ok); h.assertEqual(reason, 'item_not_exists')
    ok, reason = QBCore.Functions.RemoveItem(name)
    h.assertFalse(ok); h.assertEqual(reason, 'item_not_exists')
end)

h.test('legacy removal rejects registry failure instead of announcing partial success', function()
    local name = 'weapon_legacy_failure'
    for _, registry in ipairs({ 'items', 'weapons' }) do
        h.assertTrue(Core.registry.registerShared(registry, name, { name = name, type = 'weapon' }))
    end
    local unregister, clientEvent = Core.registry.unregisterShared, TriggerClientEvent
    local removals = 0
    TriggerClientEvent = function(event, ...)
        if event == 'QBCore:Client:OnSharedUpdate' then removals = removals + 1 end
        return clientEvent(event, ...)
    end
    Core.registry.unregisterShared = function(registry, key)
        if registry == 'weapons' and key == name then return false, 'controlled rejection' end
        return unregister(registry, key)
    end
    local ok, reason = QBCore.Functions.RemoveItem(name)
    Core.registry.unregisterShared, TriggerClientEvent = unregister, clientEvent
    h.assertFalse(ok); h.assertEqual(reason, 'controlled rejection')
    h.assertEqual(removals, 0)
    h.assertTrue(QBCore.Shared.Items[name] ~= nil)
    h.assertTrue(QBCore.Functions.RemoveItem(name), 'retry removes the remaining canonical definition')
    h.assertEqual(QBCore.Shared.Items[name], nil)
end)

h.report('compat_behavior')
