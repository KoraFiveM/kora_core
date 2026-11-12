local PI = CoreInternal.player
local operations, locks, ordinary, epochs = {}, {}, {}, {}
local roots = { money = 'money', inventory = 'items', metadata = 'metadata' }

local function provider()
    local caller = GetInvokingResource()
    if caller == 'kora_banking' or caller == Config.inventory.provider then return caller end
end

local schemaReady
function Core.persistence.awaitSchema()
    if schemaReady then return true end
    local ok, err = Kora.sql.awaitTables({ 'players', 'player_vehicles', 'kora_core_player_column_operations' }, 60000)
    if not ok then return false, err end
    schemaReady = true
    return true
end

function Core.persistence._isColumnLocked(citizenid, column)
    return locks[citizenid] and locks[citizenid][column] ~= nil or false
end

function Core.persistence._hasColumnOperation(citizenid)
    return locks[citizenid] ~= nil or ordinary[citizenid] == true
end

function Core.persistence._columnEpoch(citizenid) return epochs[citizenid] or 0 end

function Core.persistence._persistentColumnsAvailable(citizenid)
    local called, row, err = pcall(Kora.sql.single, 'SELECT `operation_key` FROM `kora_core_player_column_operations` WHERE `citizenid`=? LIMIT 1', { citizenid })
    if not called or err then return false, 'player operation storage is unavailable' end
    if row then return false, 'player data is busy' end
    local checked, active = pcall(function() return exports.kora_sql:hasActivePlayerOperation(citizenid) end)
    if not checked or active == nil then return false, 'player operation storage is unavailable' end
    if active then return false, 'player data is busy' end
    return not Core.persistence._hasColumnOperation(citizenid), 'player data is busy'
end

function Core.persistence._beginOfflineWrite(citizenid)
    if Core.persistence._hasColumnOperation(citizenid) then return false end
    ordinary[citizenid] = true
    epochs[citizenid] = (epochs[citizenid] or 0) + 1
    return true
end

function Core.persistence._endOfflineWrite(citizenid) ordinary[citizenid] = nil end

function Core.persistence._beginMoneyTransfer(citizenids)
    for _, cid in ipairs(citizenids) do if Core.persistence._hasColumnOperation(cid) then return false end end
    for _, cid in ipairs(citizenids) do ordinary[cid] = true end
    return true
end

function Core.persistence._endMoneyTransfer(citizenids)
    for _, cid in ipairs(citizenids) do ordinary[cid] = nil end
end

function Core.persistence._canWriteColumn(citizenid, column, token)
    local held = locks[citizenid] and locks[citizenid][column]
    return not held or operations[held].writeToken == token
end

local function release(operation)
    for _, cid in ipairs(operation.citizenids) do
        for _, column in ipairs(operation.columns) do locks[cid][column] = nil end
        if not next(locks[cid]) then locks[cid] = nil end
    end
    operations[operation.token] = nil
end

function Core.persistence.beginPlayerColumnOperation(key, citizenids, columns)
    local ready, readyErr = Core.persistence.awaitSchema()
    if not ready then return nil, 'unavailable', readyErr end
    local caller = provider()
    if not caller then return nil, 'rejected', 'Only configured durable providers may fence player data.' end
    if type(key) ~= 'string' or #key < 1 or #key > 240 or type(citizenids) ~= 'table' or type(columns) ~= 'table'
        or #citizenids > 128 or #columns < 1 or #columns > 3 then return nil, 'rejected', 'Invalid player operation.' end
    local ids, fields, seen = {}, {}, {}
    for _, cid in ipairs(citizenids) do
        if type(cid) ~= 'string' or #cid < 1 or #cid > 50 then return nil, 'rejected', 'Invalid character ID.' end
        if not seen[cid] then ids[#ids + 1], seen[cid] = cid, true end
    end
    seen = {}
    for _, column in ipairs(columns) do
        if not roots[column] or seen[column] then return nil, 'rejected', 'Invalid durable player column.' end
        fields[#fields + 1], seen[column] = column, true
    end
    table.sort(ids); table.sort(fields)
    local token = caller .. ':' .. key
    local fingerprint = json.encode({ ids, fields })
    local existing = operations[token]
    if existing then
        if existing.fingerprint ~= fingerprint then return nil, 'conflict', 'Operation key has different player columns.' end
        if existing.preparing then return nil, 'pending', 'Player operation is preparing.' end
        if existing.persisted then return token, 'resumed' end
    end
    for _, cid in ipairs(ids) do
        if ordinary[cid] then return nil, 'pending', 'An offline player write is pending.' end
        for _, column in ipairs(fields) do
            if Core.persistence._isColumnLocked(cid, column) and locks[cid][column] ~= token then return nil, 'pending', 'Player data is busy.' end
        end
    end
    local operation = existing or { token = token, owner = caller, key = key, citizenids = ids, columns = fields,
        fingerprint = fingerprint, writeToken = {}, preparing = true }
    operation.preparing = true
    operations[token] = operation
    local rows, snapshots = {}, {}
    for _, cid in ipairs(ids) do
        epochs[cid] = (epochs[cid] or 0) + 1
        locks[cid] = locks[cid] or {}
        for _, column in ipairs(fields) do locks[cid][column] = token end
        local player = PI.byCitizenId[cid]
        if player then
            local cols = {}
            for _, column in ipairs(fields) do cols[column] = json.encode(player.PlayerData[roots[column]] or {}) end
            rows[#rows + 1] = { pk = cid, cols = cols }
            snapshots[cid] = { player = player, cols = cols }
        end
    end
    local called, flushed, err = pcall(function()
        local placeholders, present = {}, {}
        for i = 1, #ids do placeholders[i] = '?' end
        local held = {}
        if #ids > 0 then
            local stored, loadErr = Kora.sql.query('SELECT * FROM `kora_core_player_column_operations` WHERE `citizenid` IN (' .. table.concat(placeholders, ',') .. ')', ids)
            if not stored then return false, loadErr end
            held = stored
        end
        for _, lock in ipairs(held) do
            if seen[lock.column_name] then
                if lock.resource ~= caller or lock.operation_key ~= key or lock.fingerprint ~= fingerprint then return false, 'Player data is busy.' end
                present[lock.citizenid .. ':' .. lock.column_name] = true
            end
        end
        local freshRows = {}
        for _, row in ipairs(rows) do
            local cols = {}
            for column, encoded in pairs(row.cols) do
                if not present[row.pk .. ':' .. column] then cols[column] = encoded end
            end
            if next(cols) then freshRows[#freshRows + 1] = { pk = row.pk, cols = cols } end
        end
        if #freshRows > 0 then Kora.sql.enqueueMany('players', 'citizenid', freshRows, { mode = 'assign', writeMode = 'update' }) end
        if #ids > 0 then
            local drained, drainErr = Kora.sql.flush('players')
            if not drained then return false, drainErr end
        end
        local statements = {}
        for _, cid in ipairs(ids) do
            for _, column in ipairs(fields) do
                if not present[cid .. ':' .. column] then statements[#statements + 1] = {
                    query = 'INSERT INTO `kora_core_player_column_operations` (`citizenid`,`column_name`,`resource`,`operation_key`,`fingerprint`) VALUES (?,?,?,?,?)',
                    values = { cid, column, caller, key, fingerprint }, expectedRows = 1,
                } end
            end
        end
        if #statements > 0 then
            operation.uncertain = true
            local outcome, writeErr = Kora.sql.transactionChecked(statements, { key = 'kora_core:fence:' .. token, fingerprint = fingerprint, citizenids = ids })
            if not outcome or not outcome.success then
                operation.uncertain = not outcome or outcome.code == 'indeterminate'
                return false, writeErr or outcome and outcome.message
            end
            operation.uncertain = false
        end
        operation.persisted = true
        return true
    end)
    if not called or not flushed then
        operation.preparing = false
        if not operation.uncertain then release(operation) end
        return nil, operation.uncertain and 'indeterminate' or 'unavailable', tostring(err or flushed or 'Player persistence could not be confirmed.')
    end
    for _, snapshot in pairs(snapshots) do
        for column, encoded in pairs(snapshot.cols) do
            snapshot.player._encoded[column], snapshot.player._dirty[column] = encoded, nil
        end
    end
    operation.preparing = false
    return token
end

function Core.persistence.finishPlayerColumnOperation(token, committed)
    local operation = operations[token]
    if not operation or operation.owner ~= provider() then return false, 'Unknown player operation.' end
    if operation.preparing or type(committed) ~= 'table' then return false, 'Player operation is not ready.' end
    for _, cid in ipairs(operation.citizenids) do
        for _, column in ipairs(operation.columns) do
            if type(committed[cid]) ~= 'table' or type(committed[cid][column]) ~= 'table' then
                return false, 'Committed player values are required.'
            end
        end
    end
    for _, cid in ipairs(operation.citizenids) do
        local player = PI.byCitizenId[cid]
        if player then
            for _, column in ipairs(operation.columns) do
                local value = Core.util.deepClone(committed[cid][column])
                local ok, err = Core.player.setPath(player.source, { roots[column] }, value, { _columnOperationToken = operation.writeToken })
                if not ok then return false, err end
                player._encoded[column], player._dirty[column] = json.encode(value), nil
            end
            if Core.money and Core.money.syncState then Core.money.syncState(player.source) end
        end
    end
    local removed, removeErr = Kora.sql.update('DELETE FROM `kora_core_player_column_operations` WHERE `resource`=? AND `operation_key`=?', { operation.owner, operation.key })
    if removed == nil then return false, removeErr or 'Could not release the committed player operation.' end
    release(operation)
    return true
end

function Core.persistence.abortPlayerColumnOperation(token)
    local operation = operations[token]
    if not operation or operation.owner ~= provider() or operation.preparing then return false, 'Unknown player operation.' end
    local removed, err = Kora.sql.update('DELETE FROM `kora_core_player_column_operations` WHERE `resource`=? AND `operation_key`=?', { operation.owner, operation.key })
    if removed == nil then return false, err or 'Could not release the rolled-back player operation.' end
    release(operation)
    return true
end

function Core.persistence.getPlayerColumnOperations()
    local caller, result = provider(), {}
    if not caller then return result end
    local ready, readyErr = Core.persistence.awaitSchema()
    if not ready then error(readyErr or 'Player operation storage unavailable') end
    local stored, err = Kora.sql.query('SELECT * FROM `kora_core_player_column_operations` WHERE `resource`=?', { caller })
    if not stored then error(err or 'Player operation storage unavailable') end
    for _, row in ipairs(stored) do
        local token = caller .. ':' .. row.operation_key
        if not operations[token] then
            local definition = json.decode(row.fingerprint)
            operations[token] = { token = token, owner = caller, key = row.operation_key, citizenids = definition[1], columns = definition[2],
                fingerprint = row.fingerprint, writeToken = {}, persisted = true, preparing = false }
            for _, cid in ipairs(definition[1]) do
                epochs[cid] = (epochs[cid] or 0) + 1
                locks[cid] = locks[cid] or {}
                for _, column in ipairs(definition[2]) do locks[cid][column] = token end
            end
        end
    end
    for token, operation in pairs(operations) do
        if operation.owner == caller then result[#result + 1] = {
            token = token, operationKey = operation.key, citizenids = Core.util.deepClone(operation.citizenids),
            columns = Core.util.deepClone(operation.columns), preparing = operation.preparing,
        } end
    end
    return result
end
