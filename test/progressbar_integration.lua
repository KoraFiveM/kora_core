-- Run from qbcore: lua test/progressbar_integration.lua /path/to/kora_lib
local kora_lib = assert(arg[1], 'pass the kora_lib resource directory')
local h = dofile('test/harness.lua')
local handle = dofile('test/mocks.lua').install({ client = true })
dofile('config.lua')
for _, name in ipairs({ 'items', 'jobs', 'gangs', 'vehicles', 'weapons', 'locations' }) do
    dofile('shared/' .. name .. '.lua')
end
dofile('modules/util/shared.lua')
dofile('modules/registry/shared.lua'); dofile('modules/registry/client.lua')
dofile('modules/player/shared.lua'); dofile('modules/player/client.lua')
dofile('compat/shared/coreobject.lua'); dofile('compat/client/qb-core.lua')

local invoker, resource = 'legacy_job', 'kora_core'
GetInvokingResource = function() return invoker end
GetCurrentResourceName = function() return resource end
IsEntityDead = function() return false end
PlayerPedId = function() return 1 end
LocalPlayer = { state = { inv_busy = false } }
function LocalPlayer.state:set(key, value) self[key] = value end
QB.compat.isCallable = QB.util.isCallable
local acquired, released = {}, {}
QB.compat.acquireControls = function(controls, options, owner)
    acquired[#acquired + 1] = { owner = owner, controls = controls }
    return #acquired
end
QB.compat.releaseControlLease = function(id, owner) released[#released + 1] = { id = id, owner = owner } end
local running, cancelled, activeOwner, nativePayload
QB.progressbar.validate = function() end
QB.progressbar.isActive = function() return running == true end
QB.progressbar.start = function(payload, owner)
    nativePayload, activeOwner, running, cancelled = payload, owner, true, false
    coroutine.yield()
    running = false
    return not cancelled
end
QB.progressbar.cancel = function(owner)
    h.assertEqual(owner, activeOwner, 'cancellation uses the actual legacy consumer owner')
    cancelled = true
end
resource = 'kora_lib'
dofile(kora_lib .. '/compat/client/progressbar.lua')
resource = 'kora_core'
local provider
TriggerEvent('__cfx_export_progressbar_Progress', function(fn) provider = fn end)
exports.progressbar = { Progress = function(_, ...)
    local previousInvoker, previousResource = invoker, resource
    invoker, resource = 'kora_core', 'kora_lib'
    local result = table.pack(pcall(provider, ...))
    invoker, resource = previousInvoker, previousResource
    if not result[1] then error(result[2]) end
    return table.unpack(result, 2, result.n)
end }

local directExport
TriggerEvent('__cfx_export_qb-core_Progressbar', function(fn) directExport = fn end)
for _, entry in ipairs({ QBCore.Functions.Progressbar, directExport }) do
    h.test('core progress participates in legacy cancellation and cleanup', function()
        local finished, aborted = 0, 0
        local beforeAcquired, beforeReleased = #acquired, #released
        invoker = 'legacy_job'
        entry('repair', 'Repairing', 500, false, true,
            { disableMovement = true, disableMouse = true },
            { task = 'WORLD_HUMAN_WELDING' }, nil, { model = 'prop_two' },
            function() finished = finished + 1 end, function() aborted = aborted + 1 end)
        h.assertTrue(LocalPlayer.state.inv_busy, 'the shared adapter owns inventory busy state')
        handle.step()
        h.assertEqual(activeOwner, 'legacy_job')
        h.assertEqual(nativePayload.scenario.name, 'WORLD_HUMAN_WELDING')
        h.assertEqual(nativePayload.props[1].model, 'prop_two')
        h.assertTrue(#acquired > beforeAcquired)
        TriggerEvent('progressbar:client:cancel')
        handle.step()
        h.assertEqual(finished, 0)
        h.assertEqual(aborted, 1)
        h.assertFalse(LocalPlayer.state.inv_busy)
        h.assertEqual(#released - beforeReleased, #acquired - beforeAcquired)
        h.assertEqual(released[#released].owner, 'legacy_job')
        TriggerEvent('progressbar:client:cancel')
        handle.step()
        h.assertEqual(aborted, 1, 'repeated cancellation cannot repeat the callback')
    end)
end
h.report('core_progressbar_integration')
