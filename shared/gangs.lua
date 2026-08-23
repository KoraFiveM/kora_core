-- Seed gang definitions. Same one-based graded shape as jobs (see
-- shared/jobs.lua); keyed by gang name.
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
