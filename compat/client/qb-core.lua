-- compat/client/qb-core.lua -- the client half of the QBCore object, exposed via
-- exports['qb-core']:GetCoreObject(). Reads come from the replicated mirror;
-- most helper functions are THIN FORWARDS to qblib (QB.*) rather than
-- reimplementations -- the whole point of building on qblib.

local function provideExport(providedResource, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(providedResource, exportName), function(setCB)
        setCB(func)
    end)
end

local F = QBCore.Functions

-- PlayerData accessors over the mirror.
function F.GetPlayerData(cb)
    local data = Core.replication.getData()
    if cb then cb(data) end
    return data
end

function F.Notify(text, type_, length) QB.notify.send({ description = text, type = type_, duration = length }) end

-- Real QBCore's TriggerCallback forwards EVERY value the server handler
-- returned to `cb`, not just the first -- qblib's QB.callback.trigger (called
-- here cross-resource, qbcore -> qblib) now supports that end to end, so
-- table.pack/unpack is all that's needed to match it faithfully.
function F.TriggerCallback(name, cb, ...)
    local results = table.pack(QB.callback.trigger(name, ...))
    if cb then cb(table.unpack(results, 1, results.n)) end
end

function F.CreateCallback(name, cb) QB.callback.register(name, cb) end

-- World helpers -> qblib.
function F.GetClosestPlayer(coords) return QB.world.getClosestEntity('player', coords) end
function F.GetClosestPed(coords) return QB.world.getClosestEntity('ped', coords) end
function F.GetClosestVehicle(coords) return QB.world.getClosestEntity('vehicle', coords) end
function F.GetClosestObject(coords) return QB.world.getClosestEntity('object', coords) end
function F.GetVehicles() return GetGamePool('CVehicle') end
function F.GetPeds() return GetGamePool('CPed') end

function F.Draw3DText(coords, text, opts) QB.drawing.text3d(coords, text, opts) end
function F.LoadModel(model, cb) QB.stream.loadModel(model, cb) end
function F.LoadAnimDict(dict, cb) QB.stream.loadAnimDict(dict, cb) end
function F.Progressbar(name, label, duration, useWhileDead, canCancel, disable, anim, prop, propTwo, onFinish, onCancel)
    QB.progressbar.start({ label = label, duration = duration, canCancel = canCancel,
        onFinish = onFinish, onCancel = onCancel })
end

provideExport('qb-core', 'GetCoreObject', function() return QBCore end)
