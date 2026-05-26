CreateThread(function()
    Wait(750)
    BA.DetectFramework()
    TriggerServerEvent('BA_Core:server:requestFramework')
end)

RegisterNetEvent('BA_Core:client:frameworkReady', function(framework)
    BA.Framework = framework
    TriggerEvent('BA_Core:client:ready', framework)
end)

exports('GetFramework', BA.GetFramework)
exports('GetFrameworkName', BA.GetFrameworkName)
exports('IsFrameworkReady', BA.IsFrameworkReady)
