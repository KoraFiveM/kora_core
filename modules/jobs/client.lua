---@return table|nil
function Core.jobs.getJob()
    return Core.replication.getData({ 'job' })
end
---@return table|nil
function Core.jobs.getGang()
    return Core.replication.getData({ 'gang' })
end
