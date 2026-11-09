---Register a command. handler(source, args, rawCommand).
---@param name string
---@param help string
---@param args table|nil    -- { {name=, help=}, ... } for chat suggestions
---@param argsRequired boolean|nil
---@param handler fun(source:integer, args:string[], raw:string)
---@param permission string|nil  -- default 'user'
function Core.commands.addCommand(name, help, args, argsRequired, handler, permission)
    Kora.commands.add(name, help, args, argsRequired, handler, {
        permission = permission or 'user',
        resource = GetInvokingResource() or GetCurrentResourceName(),
        checkPermission = Core.permissions.hasPermission,
        notify = function(src, message, type_) TriggerClientEvent('QBCore:Notify', src, message, type_) end,
    })
end

---@param name string
function Core.commands.removeCommand(name)
    Kora.commands.remove(name)
end

---Re-send all chat suggestions to one source (on (re)connect).
---@param src integer
function Core.commands.refreshCommands(src)
    Kora.commands.refresh(src)
end

---@return table[]  -- {name, help, permission} for each command
function Core.commands.listCommands()
    return Kora.commands.list()
end
