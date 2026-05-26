BA = BA or {}
BA.Framework = BA.Framework or {
    name = 'unknown',
    object = nil,
    ready = false
}

function BA.Framework.Detect()
    if GetResourceState('ba_core') ~= 'started' then
        BA.Framework.name = 'unknown'
        BA.Framework.object = nil
        BA.Framework.ready = false
        return BA.Framework
    end

    local ok, framework = pcall(function()
        return exports['ba_core']:GetFramework()
    end)

    if ok and type(framework) == 'table' then
        BA.Framework.name = framework.name or 'unknown'
        BA.Framework.object = framework.object
        BA.Framework.ready = framework.ready == true
        return BA.Framework
    end

    BA.Framework.name = 'unknown'
    BA.Framework.object = nil
    BA.Framework.ready = false
    return BA.Framework
end

function BA.Framework.GetObject()
    return BA.Framework.Detect().object
end

function BA.Framework.GetName()
    return BA.Framework.Detect().name
end

function BA.Framework.IsReady()
    return BA.Framework.Detect().ready == true
end
