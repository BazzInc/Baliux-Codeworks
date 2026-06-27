local blockedModels = {}
local protectedPeds = {}
local protectedVehicles = {}
local guardedPeds = {}

local function cacheBlockedModels()
    blockedModels = {}

    for _, modelName in ipairs(Config.BlockedVehicleModels or {}) do
        blockedModels[joaat(modelName)] = true
    end
end

local function isPlayerPed(ped)
    return ped ~= 0 and DoesEntityExist(ped) and IsPedAPlayer(ped)
end

local function hasPlayerOccupant(vehicle)
    if not DoesEntityExist(vehicle) then
        return false
    end

    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if isPlayerPed(GetPedInVehicleSeat(vehicle, seat)) then
            return true
        end
    end

    return false
end

local function hasNpcOccupant(vehicle)
    if not DoesEntityExist(vehicle) then
        return false
    end

    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
            return true
        end
    end

    return false
end

local function isBlockedVehicle(vehicle)
    if blockedModels[GetEntityModel(vehicle)] then
        return true
    end

    return Config.BlockedVehicleClasses[GetVehicleClass(vehicle)] == true
end

local function removeBlockedAmbientVehicles()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local maxDistance = Config.Scan.maxDistance or 220.0

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle)
            and #(GetEntityCoords(vehicle) - playerCoords) <= maxDistance
            and not hasPlayerOccupant(vehicle)
            and isBlockedVehicle(vehicle)
        then
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteEntity(vehicle)
        end
    end
end

local function guardNpcVehicles()
    local playerCoords = GetEntityCoords(PlayerPedId())
    local maxDistance = Config.Scan.maxDistance or 220.0

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle)
            and #(GetEntityCoords(vehicle) - playerCoords) <= maxDistance
            and not hasPlayerOccupant(vehicle)
            and hasNpcOccupant(vehicle)
        then
            if Config.ProtectNpcVehicles and not protectedVehicles[vehicle] then
                SetEntityInvincible(vehicle, true)
                SetEntityProofs(vehicle, true, true, true, true, true, true, true, true)
                SetVehicleCanBreak(vehicle, false)
                SetVehicleTyresCanBurst(vehicle, false)
                protectedVehicles[vehicle] = true
            end

            for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
                local ped = GetPedInVehicleSeat(vehicle, seat)
                if ped ~= 0 and DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                    if Config.CalmNpcDrivers and seat == -1 then
                        SetDriverAbility(ped, 0.6)
                        SetDriverAggressiveness(ped, 0.0)
                    end

                    if Config.ProtectVehicleNpcs and not protectedPeds[ped] then
                        SetEntityInvincible(ped, true)
                        SetEntityProofs(ped, true, true, true, false, true, true, true, true)
                        SetPedDiesWhenInjured(ped, false)
                        SetPedSuffersCriticalHits(ped, false)
                        SetPedDropsWeaponsWhenDead(ped, false)
                        protectedPeds[ped] = true
                    end

                    if Config.IgnoreWeaponsAndViolence then
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        SetPedFleeAttributes(ped, 0, false)
                        SetPedCanBeDraggedOut(ped, false)
                        SetPedStayInVehicleWhenJacked(ped, true)
                        SetPedCanBeTargetted(ped, false)
                        SetPedCanRagdoll(ped, false)
                        SetPedCanRagdollFromPlayerImpact(ped, false)
                        SetPedSeeingRange(ped, 0.0)
                        SetPedHearingRange(ped, 0.0)
                        SetPedAlertness(ped, 0)
                        SetPedConfigFlag(ped, 32, false)
                        SetPedConfigFlag(ped, 281, true)
                        SetPedConfigFlag(ped, 294, true)

                        if not guardedPeds[ped] then
                            SetPedKeepTask(ped, true)
                            guardedPeds[ped] = true
                        end
                    end
                end
            end
        end
    end
end

local function stopPlayerCarjacking()
    if not Config.PreventNpcVehicleStealing then
        return
    end

    local targetVehicle = GetVehiclePedIsTryingToEnter(PlayerPedId())

    if targetVehicle ~= 0 and DoesEntityExist(targetVehicle) and hasNpcOccupant(targetVehicle) and not hasPlayerOccupant(targetVehicle) then
        ClearPedTasksImmediately(PlayerPedId())
    end
end

local function ignoreWeaponsAndViolence()
    if not Config.IgnoreWeaponsAndViolence then
        return
    end

    local playerId = PlayerId()
    SetEveryoneIgnorePlayer(playerId, true)
    SetIgnoreLowPriorityShockingEvents(playerId, true)
end

local function applyPopulationControl()
    local trafficDensity = Config.TrafficDensity or 0.45

    SetVehicleDensityMultiplierThisFrame(trafficDensity)
    SetRandomVehicleDensityMultiplierThisFrame(trafficDensity)
    SetParkedVehicleDensityMultiplierThisFrame(Config.NoParkedVehicles and 0.0 or trafficDensity)

    if Config.NoWalkingPeds then
        SetPedDensityMultiplierThisFrame(0.0)
    end

    if Config.NoScenarioPeds then
        SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
    end
end

local function disableCopsDispatchWanted()
    if not Config.NoCopsDispatchWanted then
        return
    end

    SetCreateRandomCops(false)
    SetCreateRandomCopsNotOnScenarios(false)
    SetCreateRandomCopsOnScenarios(false)

    for i = 1, 15 do
        EnableDispatchService(i, false)
    end

    local playerId = PlayerId()
    SetMaxWantedLevel(0)
    SetPlayerWantedLevel(playerId, 0, false)
    SetPlayerWantedLevelNow(playerId, false)
    SetPoliceIgnorePlayer(playerId, true)
end

CreateThread(function()
    cacheBlockedModels()

    while true do
        applyPopulationControl()
        disableCopsDispatchWanted()
        stopPlayerCarjacking()
        ignoreWeaponsAndViolence()
        Wait(0)
    end
end)

CreateThread(function()
    while true do
        removeBlockedAmbientVehicles()
        Wait(Config.Scan.interval or 1000)
    end
end)

CreateThread(function()
    while true do
        guardNpcVehicles()
        Wait(Config.Scan.npcInterval or 250)
    end
end)
