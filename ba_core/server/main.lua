CreateThread(function()
    Wait(500)
    local framework = BA.DetectFramework()
    TriggerEvent('BA_Core:server:frameworkReady', framework)
end)

RegisterNetEvent('BA_Core:server:requestFramework', function()
    local src = source
    TriggerClientEvent('BA_Core:client:frameworkReady', src, BA.GetFramework())
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    Wait(500)
    local framework = BA.DetectFramework()
    TriggerEvent('BA_Core:server:frameworkReady', framework)
end)

exports('GetFramework', BA.GetFramework)
exports('GetFrameworkName', BA.GetFrameworkName)
exports('IsFrameworkReady', BA.IsFrameworkReady)
