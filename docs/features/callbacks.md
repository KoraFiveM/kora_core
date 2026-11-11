---
title: Callbacks
sidebar_position: 10
---

# Callbacks

New code should use kora_lib's callbacks directly (`Kora.callback.register` and
`Kora.callback.trigger`). kora_core adds a bridge so a callback is reachable over
both the Kora transport and the legacy QBCore event wire.

## Server callbacks

```lua
-- server
exports.kora_core:createCallback('myres:getBalance', function(source, reply, account)
    reply(exports.kora_core:getMoney(source, account))
end)
```

`createCallback(name, handler)` (also `QBCore.Functions.CreateCallback`) registers
`handler(source, reply, ...)`:

- on the legacy wire: the client event `QBCore:Server:TriggerCallback` calls the
  handler and the reply is sent back with `QBCore:Client:TriggerCallback`;
- on the Kora wire: `Kora.callback.register(name, ...)`; if the handler does not
  call `reply` within `Config.compat.callbackTimeoutMs` (5000 ms by default) the
  request is answered with no values.

```lua
-- client, native
local balance = Kora.callback.trigger('myres:getBalance', 'bank')

-- client, legacy (callback form)
QBCore.Functions.TriggerCallback('myres:getBalance', function(balance) end, 'bank')

-- client, legacy (await form, must run inside a thread)
CreateThread(function()
    local balance = QBCore.Functions.TriggerCallback('myres:getBalance', 'bank')
end)
```

Client `QBCore.Functions.TriggerCallback(name, ...)` follows qb-core 1.3.0: a
function as the first argument after the name is the callback; otherwise the call
awaits and returns the reply. The await form errors when not called from a thread
and resolves `nil` after `Config.compat.callbackTimeoutMs`. Concurrent calls with
the same name are answered first in, first out, because the reply carries only the
name. A leading `nil` is forwarded and selects the await form.

Server `QBCore.Functions.TriggerCallback(name, source, cb, ...)` runs the
callback through `Kora.callback.trigger(source, name, ...)` and passes the results
to `cb`.

## Client callbacks

```lua
-- client
QBCore.Functions.CreateClientCallback('myres:getStreet', function(reply)
    local coords = GetEntityCoords(PlayerPedId())
    reply(GetStreetNameFromHashKey(GetStreetNameAtCoord(coords.x, coords.y, coords.z)))
end)

-- server
QBCore.Functions.TriggerClientCallback('myres:getStreet', source, function(street) end)
local street = QBCore.Functions.TriggerClientCallback('myres:getStreet', source) -- await form
```

`CreateClientCallback` (and the client `QBCore.Functions.CreateCallback`) registers
the handler on `QBCore:Client:TriggerClientCallback` and on the Kora client
transport, with the same timeout. `TriggerClientCallback` stores the callback or a
promise under `name .. source` and resolves it from
`QBCore:Server:TriggerClientCallback`.

## Callbacks registered by kora_core

| Name | Realm | Returns |
| --- | --- | --- |
| `QBCore:Server:SpawnVehicle` | server | Network ID or `nil`; see [Vehicle spawn](../vehicle-spawn.md). |
| `QBCore:Server:CreateVehicle` | server | Network ID or `nil`. |
| `qb-multicharacter:server:GetUserCharacters` | server (Kora wire) | All active `players` rows of the caller's license. |
| `qb-multicharacter:server:GetNumberOfCharacters` | server (Kora wire) | The caller's slot cap and an empty table. |
| `qb-multicharacter:server:setupCharacters` | server (Kora wire) | `getCharacters(source)` summaries. |
| `qb-multicharacter:server:getSkin` | server (Kora wire) | Always `nil`. |
| `qb-multicharacter:server:deleteCharacter` | server (Kora wire) | `deleteCharacter(source, citizenid)` result. |
| `qb-spawn:server:getOwnedHouses` | server (Kora wire) | Always an empty table. |
