BAConfig = BAConfig or {}

-- auto = erkennt ESX/QB automatisch, sonst: 'esx', 'qb', 'standalone'
BAConfig.Framework = 'auto'

BAConfig.Debug = true

BAConfig.FrameworkResources = {
    esx = {
        'es_extended'
    },
    qb = {
        'qb-core'
    }
}
