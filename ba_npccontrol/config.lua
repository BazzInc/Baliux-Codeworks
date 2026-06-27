Config = {}

Config.Debug = false

-- 0.0 = aus, 1.0 = Standard
Config.TrafficDensity = 0.1

Config.NoParkedVehicles = true
Config.NoWalkingPeds = true
Config.NoScenarioPeds = true
Config.NoCopsDispatchWanted = true

Config.ProtectVehicleNpcs = true
Config.PreventNpcVehicleStealing = true
Config.IgnoreWeaponsAndViolence = true
Config.ProtectNpcVehicles = true
Config.CalmNpcDrivers = true

Config.Scan = {
    interval = 1000,
    npcInterval = 0,
    maxDistance = 220.0
}

Config.BlockedVehicleClasses = {
    [18] = true,
    [19] = true
}

Config.BlockedVehicleModels = {
    'ambulance',
    'firetruk',
    'fbi',
    'fbi2',
    'lguard',
    'police',
    'police2',
    'police3',
    'police4',
    'policeb',
    'policeold1',
    'policeold2',
    'policet',
    'pranger',
    'riot',
    'riot2',
    'sheriff',
    'sheriff2'
}
