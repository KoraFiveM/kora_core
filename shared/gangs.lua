-- Default gang definitions. The server registers them through the runtime
-- registry. They use the same one-based graded shape as jobs (see
-- shared/jobs.lua) and are keyed by gang name.
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.gangs = {
    { name = 'none', label = 'No Gang', grades = { { name = 'None' } } },
    {
        name = 'ballas', label = 'Ballas',
        grades = { { name = 'Associate' }, { name = 'Soldier' }, { name = 'Boss', isboss = true } },
    },
    {
        name = 'vagos', label = 'Vagos',
        grades = { { name = 'Associate' }, { name = 'Soldier' }, { name = 'Boss', isboss = true } },
    },
}
