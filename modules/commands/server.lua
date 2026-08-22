-- Core.commands (server realm) -- a registration wrapper over RegisterCommand
-- with permission gating and chat-suggestion support. OWNER-TRACKED via
-- QB.resources.serverRegistry so a resource that restarts doesn't leave dead
-- command handlers behind (legacy qb-core does).

-- name -> { help, args, argsRequired, handler, permission, resource }
local commands = {}

local cmdRegistry = QB.resources.serverRegistry(function(owner)
    for name, def in pairs(commands) do
        if def.resource == owner then
            commands[name] = nil
            -- Re-suggest removal to all clients.
            TriggerClientEvent('chat:removeSuggestion', -1, '/' .. name)
        end
    end
end)

---Register a command. handler(source, args, rawCommand).
---@param name string
---@param help string
---@param args table|nil    -- { {name=, help=}, ... } for chat suggestions
---@param argsRequired boolean|nil
---@param handler fun(source:integer, args:string[], raw:string)
---@param permission string|nil  -- default 'user'
function Core.commands.addCommand(name, help, args, argsRequired, handler, permission)
    permission = permission or 'user'
    local owner = GetInvokingResource() or GetCurrentResourceName()
    commands[name] = {
        help = help, args = args, argsRequired = argsRequired,
        handler = handler, permission = permission, resource = owner,
    }
    if owner then cmdRegistry.track(owner) end

    RegisterCommand(name, function(source, rawArgs, raw)
        local def = commands[name]
        if not def then return end
        if source ~= 0 and def.permission ~= 'user' and not Core.permissions.hasPermission(source, def.permission) then
            TriggerClientEvent('QBCore:Notify', source, 'You do not have permission for this command.', 'error')
            return
        end
        if def.argsRequired and def.args and #rawArgs < #def.args then
            TriggerClientEvent('QBCore:Notify', source, ('Missing arguments for /%s'):format(name), 'error')
            return
        end
        local ok, err = pcall(def.handler, source, rawArgs, raw)
        if not ok then print(("^3[qbcore:commands]^7 /%s errored: %s"):format(name, tostring(err))) end
    end, false)

    -- Chat suggestion.
    TriggerClientEvent('chat:addSuggestion', -1, '/' .. name, help or '', args or {})
end

---@param name string
function Core.commands.removeCommand(name)
    commands[name] = nil
    TriggerClientEvent('chat:removeSuggestion', -1, '/' .. name)
end

---Re-send all chat suggestions to one source (on (re)connect).
---@param src integer
function Core.commands.refreshCommands(src)
    for name, def in pairs(commands) do
        TriggerClientEvent('chat:addSuggestion', src, '/' .. name, def.help or '', def.args or {})
    end
end

---@return table[]  -- {name, help, permission} for each command
function Core.commands.listCommands()
    local out = {}
    for name, def in pairs(commands) do
        out[#out + 1] = { name = name, help = def.help, permission = def.permission }
    end
    return out
end
