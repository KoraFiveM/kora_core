-- Seed gang definitions. Same graded shape as jobs; keyed by gang name.
QBCoreSeed = QBCoreSeed or {}

QBCoreSeed.gangs = {
    { name = 'none', label = 'No Gang', grades = { [0] = { name = 'None' } } },
    {
        name = 'ballas', label = 'Ballas',
        grades = { [0] = { name = 'Associate' }, [1] = { name = 'Soldier' }, [2] = { name = 'Boss', isboss = true } },
    },
    {
        name = 'vagos', label = 'Vagos',
        grades = { [0] = { name = 'Associate' }, [1] = { name = 'Soldier' }, [2] = { name = 'Boss', isboss = true } },
    },
}
