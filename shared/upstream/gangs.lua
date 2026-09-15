-- Compatibility snapshot from qbcore-framework/qb-core main at
-- 9b3cddcce93e5e12cbcf6b47b866b687d32ac7bf. Keep this keyed upstream shape
-- isolated; shared/upstream/merge.lua adapts it to qbcore's seed registry.
QBCoreUpstream = QBCoreUpstream or {}

QBCoreUpstream.gangs = {
    none = { label = 'No Gang', grades = { ['0'] = { name = 'Unaffiliated' } } },
    lostmc = {
        label = 'The Lost MC',
        grades = {
            ['0'] = { name = 'Recruit' },
            ['1'] = { name = 'Enforcer' },
            ['2'] = { name = 'Shot Caller' },
            ['3'] = { name = 'Boss', isboss = true },
        },
    },
    ballas = {
        label = 'Ballas',
        grades = {
            ['0'] = { name = 'Recruit' },
            ['1'] = { name = 'Enforcer' },
            ['2'] = { name = 'Shot Caller' },
            ['3'] = { name = 'Boss', isboss = true },
        },
    },
    vagos = {
        label = 'Vagos',
        grades = {
            ['0'] = { name = 'Recruit' },
            ['1'] = { name = 'Enforcer' },
            ['2'] = { name = 'Shot Caller' },
            ['3'] = { name = 'Boss', isboss = true },
        },
    },
    cartel = {
        label = 'Cartel',
        grades = {
            ['0'] = { name = 'Recruit' },
            ['1'] = { name = 'Enforcer' },
            ['2'] = { name = 'Shot Caller' },
            ['3'] = { name = 'Boss', isboss = true },
        },
    },
    families = {
        label = 'Families',
        grades = {
            ['0'] = { name = 'Recruit' },
            ['1'] = { name = 'Enforcer' },
            ['2'] = { name = 'Shot Caller' },
            ['3'] = { name = 'Boss', isboss = true },
        },
    },
    triads = {
        label = 'Triads',
        grades = {
            ['0'] = { name = 'Recruit' },
            ['1'] = { name = 'Enforcer' },
            ['2'] = { name = 'Shot Caller' },
            ['3'] = { name = 'Boss', isboss = true },
        },
    }
}
