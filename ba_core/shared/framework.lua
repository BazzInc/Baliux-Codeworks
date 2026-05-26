BA = BA or {}
BA.Framework = BA.Framework or {
    name = 'unknown',
    object = nil,
    ready = false
}

local function debugPrint(message)
    if BAConfig and BAConfig.Debug then
        print(('[BA_Core] %s'):format(message))
    end
end

local function resourceStarted(resourceName)
    return GetResourceState(resourceName) == 'started'
end

local function detectFrameworkName()
    local configured = BAConfig.Framework or 'auto'

    if configured ~= 'auto' then
        return configured
    end

    for _, resourceName in ipairs(BAConfig.FrameworkResources.esx or {}) do
        if resourceStarted(resourceName) then
            return 'esx'
        end
    end

    for _, resourceName in ipairs(BAConfig.FrameworkResources.qb or {}) do
        if resourceStarted(resourceName) then
            return 'qb'
        end
    end

    return 'standalone'
end

function BA.DetectFramework()
    BA.Framework.name = detectFrameworkName()
    BA.Framework.ready = false
    BA.Framework.object = nil

    if BA.Framework.name == 'esx' then
        local ok, obj = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)

        if ok and obj then
            BA.Framework.object = obj
            BA.Framework.ready = true
            debugPrint('ESX erkannt und geladen.')
            return BA.Framework
        end

        debugPrint('ESX erkannt, aber Objekt konnte nicht geladen werden.')
        return BA.Framework
    end

    if BA.Framework.name == 'qb' then
        local ok, obj = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)

        if ok and obj then
            BA.Framework.object = obj
            BA.Framework.ready = true
            debugPrint('QB-Core erkannt und geladen.')
            return BA.Framework
        end

        debugPrint('QB-Core erkannt, aber Objekt konnte nicht geladen werden.')
        return BA.Framework
    end

    BA.Framework.name = 'standalone'
    BA.Framework.ready = true
    debugPrint('Kein Framework erkannt. Standalone-Modus aktiv.')
    return BA.Framework
end

function BA.GetFramework()
    return BA.Framework
end

function BA.GetFrameworkName()
    return BA.Framework.name
end

function BA.IsFrameworkReady()
    return BA.Framework.ready == true
end

exports('GetFramework', BA.GetFramework)
exports('GetFrameworkName', BA.GetFrameworkName)
exports('IsFrameworkReady', BA.IsFrameworkReady)
