-- usage: lua boot.lua <db> [legacyState]  (cwd = kora_core; env MARIADB). Runs the REAL
-- modules/persistence/migrate.lua boot flow against a compat_scratch_* database.
local db, opt = arg[1], arg[2]
local mariadb = os.getenv('MARIADB') or 'sudo mariadb'
local tmp = os.tmpname()
assert(db:match('^compat_scratch_'), 'refusing non compat_scratch_ db')
local h = dofile('test/harness.lua')
local mocks = dofile('test/mocks.lua'); local handle = mocks.install()
dofile('config.lua')
dofile('build/initiate.lua')
Config.persistence.legacyVehicleState = (opt == 'legacyState')
local function sh(sql)
    local f = assert(io.open(tmp, 'w')); f:write(sql); f:close()
    local p = io.popen(mariadb .. ' -B ' .. db .. ' < ' .. tmp .. ' 2>&1; echo "EXIT:$?"')
    local out = p:read('a'); p:close()
    local code = out:match('EXIT:(%d+)%s*$'); out = out:gsub('EXIT:%d+%s*$', '')
    return tonumber(code) == 0, out
end
local function bind(sql, params)
    local i = 0
    return (sql:gsub('%?', function() i = i + 1; return "'" .. tostring(params[i]):gsub("'", "''") .. "'" end))
end
Kora.sql.NULL = Kora.sql.NULL or {}
-- The scratch databases model installs that already ran the retired sql/*.sql
-- chain (kept under test/sql/scratch/legacy), so ensureTables/migrate are no-op stubs.
Kora.sql.ensureTables = function()
    local p = io.popen('node test/sql/scratch/apply.js ' .. db .. ' test/sql/scratch/legacy 2>&1; echo "EXIT:$?"'); local out = p:read('a'); p:close()
    io.write(out:gsub('EXIT:%d+%s*$', ''))
    if out:match('EXIT:0') then return {} end
    return nil, 'migration failed'
end
Kora.sql.migrate = function() return true end
Kora.util = Kora.util or {}
Kora.util.fnv1a = Kora.util.fnv1a or function() return '00000000' end
dofile('modules/persistence/schema.lua')
Kora.sql.query = function(sql, params)
    local ok, out = sh(bind(sql, params or {}))
    if not ok then return nil, out end
    local rows, cols = {}, nil
    for line in out:gmatch('[^\n]+') do
        local f = {}; for v in (line .. '\t'):gmatch('(.-)\t') do f[#f + 1] = v end
        if not cols then cols = f else
            local r = {}; for i, c in ipairs(cols) do r[c] = f[i] end; rows[#rows + 1] = r end
    end
    return rows
end
Kora.sql.execute = function(sql, params)
    io.write('  [sql] ', (sql:gsub('%s+', ' '):sub(1, 110)), '\n')
    local ok, out = sh(bind(sql, params or {}))
    if not ok then print('  [SQL ERROR] ' .. out); return nil, out end
    return { affectedRows = 1 }
end
dofile('modules/persistence/migrate.lua')
handle.step()
