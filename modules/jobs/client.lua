-- Core.jobs (client realm) -- read the local job/gang from the mirror.
---@return table|nil
function Core.jobs.getJob()
    return Core.replication.getData({ 'job' })
end
---@return table|nil
function Core.jobs.getGang()
    return Core.replication.getData({ 'gang' })
end
