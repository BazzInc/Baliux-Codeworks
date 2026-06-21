local ESX = nil
local currentUi = nil
local currentRestaurant = nil
local restaurants = {}
local refreshMonitorOrders
local rebuildInteractionTargets
local playMonitorSound
local openUi

local function reopenCreator(restaurantId)
    SetTimeout(300, function()
        openUi('admin', restaurantId)
    end)
end

local function resetNuiFocus()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

CreateThread(function()
    while true do
        local fw = BA.Framework.Detect()
        if fw and fw.name == 'esx' and fw.object then
            ESX = fw.object
            break
        end
        Wait(250)
    end
end)

local function notify(msg, ntype)
    if ESX and Config.Notifications.useESX and ESX.ShowNotification then
        ESX.ShowNotification(msg)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(msg)
        EndTextCommandThefeedPostTicker(false, false)
    end
end

RegisterNetEvent('ba_restaurant:notify', notify)

local function drawText3D(coords, text)
    SetDrawOrigin(coords.x, coords.y, coords.z + 0.15, 0)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextCentre(1)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local callbackRequestId = 0

local function serverCallback(name, cb, ...)
    callbackRequestId = callbackRequestId + 1
    local requestId = callbackRequestId
    local eventName = name .. ':response'
    local handler
    handler = RegisterNetEvent(eventName, function(responseId, result)
        if responseId ~= requestId then return end
        RemoveEventHandler(handler)
        cb(result)
    end)
    TriggerServerEvent(name, requestId, ...)
end

local function refreshRestaurants(cb)
    serverCallback('ba_restaurant:getRestaurants', function(result)
        restaurants = result or {}
        if rebuildInteractionTargets then rebuildInteractionTargets() end
        if cb then cb(restaurants) end
    end)
end

function openUi(typeName, restaurantId)
    currentUi = typeName
    currentRestaurant = restaurantId
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)

    if typeName == 'terminal' then
        serverCallback('ba_restaurant:getMenu', function(menu)
            SendNUIMessage({ action = 'open', view = 'terminal', restaurantId = restaurantId, payload = menu })
        end, restaurantId)
    elseif typeName == 'manager' then
        serverCallback('ba_restaurant:getManagerData', function(data)
            if data and data.ok == false then
                notify(data.error or 'Keine Berechtigung fuer den Manager-Laptop.', 'error')
                SendNUIMessage({ action = 'forceClose' })
                resetNuiFocus()
                currentUi = nil
                currentRestaurant = nil
                return
            end
            SendNUIMessage({ action = 'open', view = 'manager', restaurantId = restaurantId, payload = data })
        end, restaurantId)
    elseif typeName == 'admin' then
        serverCallback('ba_restaurant:getAdminData', function(data)
            SendNUIMessage({ action = 'open', view = 'admin', restaurantId = restaurantId or '', payload = data })
        end)
    else
        serverCallback('ba_restaurant:getOrders', function(orders)
            SendNUIMessage({ action = 'open', view = typeName, restaurantId = restaurantId, payload = { orders = orders } })
        end, restaurantId, typeName)
    end
end

local function pointPrompt(groupName)
    if groupName == 'terminals' then return 'Bestellen', 'terminal' end
    if groupName == 'manager' then return 'Produkte verwalten', 'manager' end
    if groupName == 'kitchen' then return 'Kuechensteuerung', 'kitchen' end
    if groupName == 'pickup' then return 'Abholmonitor', 'pickup' end
    if groupName == 'cashier' then return 'Kasse', 'cashier' end
    return 'Öffnen', groupName
end

local function canSeePoint(restaurant, groupName)
    local perms = restaurant.permissions or {}
    -- Öffentlich sichtbar/nutzbar
    if groupName == 'terminals' or groupName == 'pickup' then return true end

    -- Normale Ingame-Punkte sind NICHT für Admins freigeschaltet.
    -- Admins nutzen den /restaurantcreator. Dadurch sieht man fremde Manager-Laptops/Kassen nicht nur wegen ACE-Rechten.
    if groupName == 'manager' then return perms.boss == true end
    if groupName == 'kitchen' or groupName == 'cashier' then return perms.employee == true end
    return false
end

local function isLiveTvPoint(groupName)
    if groupName ~= 'kitchen' and groupName ~= 'pickup' then return false end
    local cfg = Config.MonitorLiveDisplay or {}
    if cfg.enabled ~= true or cfg.disableMonitorInteraction == false then return false end
    return not (cfg.interaction and cfg.interaction[groupName] == true)
end

local function targetEnabled()
    return Config.Target and Config.Target.enabled == true
end

local function targetResource()
    return (Config.Target and Config.Target.resource) or 'ox_target'
end

local targetZones = {}

local function clearInteractionTargets()
    local resource = targetResource()
    if resource ~= 'ox_target' or GetResourceState(resource) ~= 'started' then
        targetZones = {}
        return
    end
    for _, zoneId in ipairs(targetZones) do
        pcall(function() exports.ox_target:removeZone(zoneId) end)
    end
    targetZones = {}
end

local function targetIcon(groupName)
    if groupName == 'terminals' then return 'fa-solid fa-burger' end
    if groupName == 'manager' then return 'fa-solid fa-laptop' end
    if groupName == 'kitchen' then return 'fa-solid fa-kitchen-set' end
    if groupName == 'cashier' then return 'fa-solid fa-cash-register' end
    return 'fa-solid fa-circle'
end

rebuildInteractionTargets = function()
    clearInteractionTargets()
    if not targetEnabled() then return end

    local resource = targetResource()
    if resource ~= 'ox_target' or GetResourceState(resource) ~= 'started' then
        if Config.Debug then print(('[ba_restaurant] %s nicht gestartet: Interaktionen laufen nur ueber Third-Eye, keine E-Marker.'):format(resource)) end
        return
    end

    for restaurantId, restaurant in pairs(restaurants) do
        for _, groupName in ipairs({ 'terminals', 'manager', 'kitchen', 'cashier' }) do
            if not isLiveTvPoint(groupName) and canSeePoint(restaurant, groupName) then
                local prompt, uiName = pointPrompt(groupName)
                for index, point in ipairs((restaurant.points and restaurant.points[groupName]) or {}) do
                    local coords = vector3(point.x or point.coords.x, point.y or point.coords.y, point.z or point.coords.z)
                    local zoneId = exports.ox_target:addSphereZone({
                        coords = coords,
                        radius = Config.InteractDistance or 2.0,
                        debug = Config.Target and Config.Target.debug == true,
                        options = {
                            {
                                name = ('ba_restaurant:%s:%s:%s'):format(restaurantId, groupName, index),
                                icon = targetIcon(groupName),
                                label = point.label or prompt,
                                distance = Config.InteractDistance or 2.0,
                                onSelect = function()
                                    openUi(uiName, restaurantId)
                                end
                            }
                        }
                    })
                    targetZones[#targetZones + 1] = zoneId
                end
            end
        end
    end
end

local function checkPointGroup(restaurantId, restaurant, groupName)
    if targetEnabled() then return end
    -- Live-TV-Monitore bleiben sichtbar; nur reine Kundenanzeigen blockieren das E-Menue.
    if isLiveTvPoint(groupName) then return end
    if not canSeePoint(restaurant, groupName) then return end
    local points = restaurant.points and restaurant.points[groupName] or {}
    local ped = PlayerPedId()
    local playerCoords = GetEntityCoords(ped)
    local prompt, uiName = pointPrompt(groupName)

    for _, point in ipairs(points) do
        local coords = vector3(point.x or point.coords.x, point.y or point.coords.y, point.z or point.coords.z)
        local dist = #(playerCoords - coords)
        if dist <= Config.DrawDistance then
            DrawMarker(2, coords.x, coords.y, coords.z + 0.15, 0.0, 0.0, 0.0, 0.0, 0.0, point.heading or 0.0, 0.25, 0.25, 0.25, 255, 200, 0, 180, false, true, 2, nil, nil, false)
            if dist <= Config.InteractDistance then
                drawText3D(coords, ('[E] %s'):format(point.label or prompt))
                if IsControlJustReleased(0, Config.InteractKey) then
                    openUi(uiName, restaurantId)
                end
            end
        end
    end
end

CreateThread(function()
    Wait(1500)
    refreshRestaurants()
    while true do
        Wait(30000)
        refreshRestaurants()
    end
end)

-- Wichtig: Jobwechsel direkt übernehmen, damit Manager/Kasse/Küche sofort ein-/ausgeblendet werden.
RegisterNetEvent('esx:playerLoaded', function()
    Wait(500)
    refreshRestaurants()
end)

RegisterNetEvent('esx:setJob', function()
    Wait(250)
    refreshRestaurants()
    if currentUi == 'manager' or currentUi == 'kitchen' or currentUi == 'cashier' then
        SendNUIMessage({ action = 'forceClose' })
        resetNuiFocus()
        currentUi = nil
        currentRestaurant = nil
    end
end)

CreateThread(function()
    while true do
        if targetEnabled() then
            Wait(1000)
        else
            local sleep = 750
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            for restaurantId, restaurant in pairs(restaurants) do
                for _, group in ipairs({ 'terminals', 'manager', 'kitchen', 'pickup', 'cashier' }) do
                    for _, point in ipairs((restaurant.points and restaurant.points[group]) or {}) do
                        local coords = vector3(point.x or point.coords.x, point.y or point.coords.y, point.z or point.coords.z)
                        if #(playerCoords - coords) <= Config.DrawDistance then sleep = 0 end
                    end
                end
                checkPointGroup(restaurantId, restaurant, 'terminals')
                checkPointGroup(restaurantId, restaurant, 'manager')
                checkPointGroup(restaurantId, restaurant, 'kitchen')
                checkPointGroup(restaurantId, restaurant, 'pickup')
                checkPointGroup(restaurantId, restaurant, 'cashier')
            end
            Wait(sleep)
        end
    end
end)

RegisterNetEvent('ba_restaurant:openCreator', function()
    openUi('admin')
end)

RegisterNetEvent('ba_restaurant:restaurantsRefresh', function()
    refreshRestaurants()
    if currentUi == 'admin' then
        serverCallback('ba_restaurant:getAdminData', function(data)
            SendNUIMessage({ action = 'adminData', payload = data or {} })
        end)
    end
end)

RegisterNUICallback('close', function(_, cb)
    SendNUIMessage({ action = 'forceClose' })
    resetNuiFocus()
    currentUi = nil
    currentRestaurant = nil
    cb({ ok = true })
end)

RegisterNUICallback('createOrder', function(data, cb) TriggerServerEvent('ba_restaurant:createOrder', data) cb({ ok = true }) end)
RegisterNUICallback('soundPlaybackFailed', function(data, cb)
    if Config.Debug then
        print(('[ba_restaurant] Sound konnte in der NUI nicht abgespielt werden: %s'):format(tostring(data and data.file)))
    end
    cb({ ok = true })
end)
RegisterNUICallback('setOrderStatus', function(data, cb) TriggerServerEvent('ba_restaurant:updateOrderStatus', data.restaurantId, data.orderId, data.status) cb({ ok = true }) end)
RegisterNUICallback('cashierPayment', function(data, cb) TriggerServerEvent('ba_restaurant:cashierPayment', data) cb({ ok = true }) end)
RegisterNUICallback('saveProduct', function(data, cb) TriggerServerEvent('ba_restaurant:saveProduct', data) cb({ ok = true }) end)
RegisterNUICallback('searchOxInventoryImages', function(data, cb)
    serverCallback('ba_restaurant:searchOxInventoryImages', function(result)
        cb({ ok = true, items = result or {} })
    end, data and data.query or '')
end)
RegisterNUICallback('closeCashierShift', function(data, cb) TriggerServerEvent('ba_restaurant:closeCashierShift', data) cb({ ok = true }) end)
RegisterNUICallback('saveCategory', function(data, cb) TriggerServerEvent('ba_restaurant:saveCategory', data) cb({ ok = true }) end)
RegisterNUICallback('deleteCategory', function(data, cb) TriggerServerEvent('ba_restaurant:deleteCategory', data.restaurantId, data.id) cb({ ok = true }) end)
RegisterNUICallback('hardDeleteCategory', function(data, cb) TriggerServerEvent('ba_restaurant:hardDeleteCategory', data.restaurantId, data.id) cb({ ok = true }) end)
RegisterNUICallback('deleteProduct', function(data, cb) TriggerServerEvent('ba_restaurant:deleteProduct', data.restaurantId, data.id) cb({ ok = true }) end)
RegisterNUICallback('hardDeleteProduct', function(data, cb) TriggerServerEvent('ba_restaurant:hardDeleteProduct', data.restaurantId, data.id) cb({ ok = true }) end)
RegisterNUICallback('saveMenu', function(data, cb) TriggerServerEvent('ba_restaurant:saveMenu', data) cb({ ok = true }) end)
RegisterNUICallback('deleteMenu', function(data, cb) TriggerServerEvent('ba_restaurant:deleteMenu', data.restaurantId, data.id) cb({ ok = true }) end)

RegisterNUICallback('saveRestaurant', function(data, cb) TriggerServerEvent('ba_restaurant:adminSaveRestaurant', data) cb({ ok = true }) end)
RegisterNUICallback('deleteRestaurant', function(data, cb) TriggerServerEvent('ba_restaurant:adminDeleteRestaurant', data.restaurantId) cb({ ok = true }) end)
RegisterNUICallback('hardDeleteRestaurant', function(data, cb) TriggerServerEvent('ba_restaurant:adminHardDeleteRestaurant', data) cb({ ok = true }) end)
RegisterNUICallback('setPointHere', function(data, cb)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    TriggerServerEvent('ba_restaurant:adminSavePoint', data.restaurantId, data.pointType, coords.x, coords.y, coords.z, heading, nil, data.screenSize, data.soundEnabled, data.soundRange, data.soundVolume)
    cb({ ok = true })
end)
RegisterNUICallback('updatePointSound', function(data, cb) TriggerServerEvent('ba_restaurant:adminUpdatePointSound', data) cb({ ok = true }) end)
RegisterNUICallback('testMonitorSound', function(data, cb)
    playMonitorSound(data.pointType, tonumber(data.soundVolume) or 0.8)
    cb({ ok = true })
end)
RegisterNUICallback('deletePoint', function(data, cb) TriggerServerEvent('ba_restaurant:adminDeletePoint', data.id) cb({ ok = true }) end)
RegisterNUICallback('openRestaurantManager', function(data, cb)
    openUi('manager', data.restaurantId)
    cb({ ok = true })
end)


RegisterNetEvent('ba_restaurant:orderFailed', function()
    SendNUIMessage({ action = 'orderFailed' })
end)

RegisterNetEvent('ba_restaurant:orderCreated', function(order)
    SendNUIMessage({ action = 'orderCreated', payload = order })
    notify(('Bestellung #%s erstellt.'):format(order.orderNumber), 'success')
end)

RegisterNetEvent('ba_restaurant:kitchenRefresh', function(restaurantId)
    if refreshMonitorOrders then refreshMonitorOrders(true) end
    if currentUi == 'kitchen' and currentRestaurant == restaurantId then
        serverCallback('ba_restaurant:getOrders', function(orders) SendNUIMessage({ action = 'ordersRefresh', payload = { orders = orders } }) end, restaurantId, 'kitchen')
    end
end)

RegisterNetEvent('ba_restaurant:pickupRefresh', function(restaurantId)
    if refreshMonitorOrders then refreshMonitorOrders(true) end
    if currentUi == 'pickup' and currentRestaurant == restaurantId then
        serverCallback('ba_restaurant:getOrders', function(orders) SendNUIMessage({ action = 'ordersRefresh', payload = { orders = orders } }) end, restaurantId, 'pickup')
    end
end)



RegisterNetEvent('ba_restaurant:cashierRefresh', function(restaurantId)
    if refreshMonitorOrders then refreshMonitorOrders(true) end
    if currentUi == 'cashier' and currentRestaurant == restaurantId then
        serverCallback('ba_restaurant:getOrders', function(orders) SendNUIMessage({ action = 'ordersRefresh', payload = { orders = orders } }) end, restaurantId, 'cashier')
    end
end)

RegisterNetEvent('ba_restaurant:managerRefresh', function(restaurantId)
    if currentUi == 'manager' and currentRestaurant == restaurantId then
        serverCallback('ba_restaurant:getManagerData', function(result) SendNUIMessage({ action = 'managerData', payload = result or {} }) end, restaurantId)
    end
end)

RegisterNetEvent('ba_restaurant:menuRefresh', function(restaurantId)
    if currentUi == 'terminal' and currentRestaurant == restaurantId then
        serverCallback('ba_restaurant:getMenu', function(menu) SendNUIMessage({ action = 'menuData', payload = menu or {} }) end, restaurantId)
    end
end)

-- v0.5 Platzierbare TV-Monitore + Feinjustierung
local spawnedMonitorProps = {}
local monitorDuis = {}
local monitorOrderCache = {}
local monitorLastFetch = 0
local monitorLastDuiPayload = {}
local monitorLastDuiSent = {}
local monitorFetchSerial = {}
local monitorSoundState = {}
local monitorSoundPlayed = {}

local function monitorSoundEnabled(group)
    local cfg = Config.MonitorSounds and Config.MonitorSounds[group]
    return cfg and cfg.file and cfg.file ~= ''
end

function playMonitorSound(group, volume)
    local cfg = Config.MonitorSounds and Config.MonitorSounds[group]
    if not cfg then
        if Config.Debug then print(('[ba_restaurant] Kein MonitorSound-Config fuer %s'):format(tostring(group))) end
        return
    end
    if cfg.file and cfg.file ~= '' then
        if Config.Debug then print(('[ba_restaurant] Spiele Monitor-Sound group=%s file=%s volume=%.2f'):format(tostring(group), tostring(cfg.file), tonumber(volume or 0.8))) end
        SendNUIMessage({ action = 'playMonitorSound', file = cfg.file, volume = volume or 0.8 })
        return
    end
    PlaySoundFrontend(-1, cfg.soundName or 'CHECKPOINT_NORMAL', cfg.soundSet or 'HUD_MINI_GAME_SOUNDSET', true)
end

local function pointSoundEnabled(group, point)
    if point and point.sound_enabled ~= nil then
        return point.sound_enabled == true or tonumber(point.sound_enabled) == 1
    end
    return monitorSoundEnabled(group)
end

local function pointSoundRange(group, point)
    local range = point and tonumber(point.sound_range)
    if range and range > 0 then return range end
    return 18.0
end

local function pointSoundVolume(point)
    local volume = point and tonumber(point.sound_volume)
    if not volume then return 0.8 end
    if volume < 0.0 then return 0.0 end
    if volume > 1.0 then return 1.0 end
    return volume
end

local function audibleMonitorSoundVolume(restaurantId, group)
    local restaurant = restaurants and restaurants[restaurantId]
    if not restaurant or not restaurant.points or not restaurant.points[group] then return nil end
    local playerCoords = GetEntityCoords(PlayerPedId())
    local bestDist, bestVolume = nil, nil
    for _, point in ipairs(restaurant.points[group] or {}) do
        if pointSoundEnabled(group, point) then
            local coords = vector3(point.x or point.coords.x, point.y or point.coords.y, point.z or point.coords.z)
            local dist = #(playerCoords - coords)
            if dist <= pointSoundRange(group, point) and (not bestDist or dist < bestDist) then
                bestDist = dist
                bestVolume = pointSoundVolume(point)
            end
        end
    end
    return bestVolume
end

local function indexOrders(orders, onlyReady)
    local out = {}
    for _, order in ipairs(orders or {}) do
        if not onlyReady or order.status == 'ready' then
            out[tostring(order.id or order.order_number)] = true
        end
    end
    return out
end

local function hasNewOrder(previous, current)
    if not previous then return false end
    for id in pairs(current or {}) do
        if not previous[id] then return true end
    end
    return false
end

local function firstNewOrder(previous, current)
    if not previous then return nil end
    for id in pairs(current or {}) do
        if not previous[id] then return id end
    end
    return nil
end

local function playMonitorGroupSound(restaurantId, group, orderId)
    if not monitorSoundEnabled(group) then
        if Config.Debug then print(('[ba_restaurant] Monitor-Sound deaktiviert/keine Datei group=%s'):format(tostring(group))) end
        return
    end
    local volume = audibleMonitorSoundVolume(restaurantId, group)
    if not volume then
        if Config.Debug then print(('[ba_restaurant] Kein hoerbarer Monitor in Reichweite restaurant=%s group=%s'):format(tostring(restaurantId), tostring(group))) end
        return
    end
    local key = tostring(restaurantId) .. ':' .. tostring(group) .. ':' .. tostring(orderId or 'event')
    local now = GetGameTimer()
    if monitorSoundPlayed[key] and (now - monitorSoundPlayed[key]) < 3000 then return end
    monitorSoundPlayed[key] = now
    playMonitorSound(group, volume)
end

local function handleMonitorSounds(restaurantId, result)
    local state = monitorSoundState[restaurantId] or {}
    local kitchenNow = indexOrders(result and result.kitchen or {}, false)
    local pickupReadyNow = indexOrders(result and result.pickup or {}, true)
    local kitchenNew = firstNewOrder(state.kitchen, kitchenNow)
    local pickupNew = firstNewOrder(state.pickupReady, pickupReadyNow)
    if kitchenNew then playMonitorGroupSound(restaurantId, 'kitchen', kitchenNew) end
    if pickupNew then playMonitorGroupSound(restaurantId, 'pickup', pickupNew) end
    monitorSoundState[restaurantId] = { kitchen = kitchenNow, pickupReady = pickupReadyNow }
end

RegisterNetEvent('ba_restaurant:monitorOrderSound', function(restaurantId, group, orderId)
    if not restaurants or not restaurants[restaurantId] then
        refreshRestaurants(function()
            playMonitorGroupSound(restaurantId, group, orderId)
        end)
        return
    end
    playMonitorGroupSound(restaurantId, group, orderId)
end)

local function parseItems(itemsJson)
    local ok, items = pcall(function() return json.decode(itemsJson or '[]') end)
    if ok and type(items) == 'table' then return items end
    return {}
end

local function monitorLines(pointType, orders)
    local lines = {}
    if pointType == 'kitchen' then
        lines[#lines + 1] = '~y~KÜCHE~s~'
        if not orders or #orders == 0 then lines[#lines + 1] = 'Keine offenen Bestellungen' end
        for i, o in ipairs(orders or {}) do
            if i > ((Config.MonitorLiveDisplay and Config.MonitorLiveDisplay.maxRows) or 8) then break end
            local items = parseItems(o.items_json)
            local itemText = ''
            for idx, item in ipairs(items) do
                if idx > 3 then itemText = itemText .. ' …'; break end
                itemText = itemText .. (idx > 1 and ', ' or '') .. tostring(item.amount or 1) .. 'x ' .. tostring(item.label or 'Artikel')
            end
            local status = o.status == 'in_progress' and 'IN ARBEIT' or 'NEU'
            lines[#lines + 1] = ('#%s  %s'):format(o.order_number, status)
            if itemText ~= '' then lines[#lines + 1] = itemText end
        end
    else
        lines[#lines + 1] = '~b~ABHOLUNG~s~'
        local working, ready = {}, {}
        for _, o in ipairs(orders or {}) do
            if o.status == 'ready' then ready[#ready + 1] = '#' .. tostring(o.order_number) else working[#working + 1] = '#' .. tostring(o.order_number) end
        end
        lines[#lines + 1] = 'In Bearbeitung: ' .. (#working > 0 and table.concat(working, '  ') or '-')
        lines[#lines + 1] = '~g~Abholbereit:~s~ ' .. (#ready > 0 and table.concat(ready, '  ') or '-')
    end
    return table.concat(lines, '\n')
end

local function drawMonitorBoard(coords, heading, text)
    SetDrawOrigin(coords.x, coords.y, coords.z + 0.55, 0)
    SetTextScale(0.28, 0.28)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 235)
    SetTextCentre(1)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function monitorKey(restaurantId, group, point)
    return tostring(restaurantId) .. ':' .. tostring(group) .. ':' .. tostring(point.id or (tostring(point.x) .. ':' .. tostring(point.y) .. ':' .. tostring(point.z)))
end

local function getMonitorDui(key, group)
    local cfg = Config.MonitorLiveDisplay or {}
    if not cfg.useDuiScreen then return nil end
    if monitorDuis[key] then return monitorDuis[key] end

    local txdName = ('ba_rest_tv_%s'):format(key:gsub('[^%w_]', '_'))
    local txnName = 'screen'
    local url = ('https://cfx-nui-%s/html/index.html?tv=1&type=%s'):format(GetCurrentResourceName(), group)
    local dui = CreateDui(url, cfg.duiWidth or 1024, cfg.duiHeight or 512)
    local handle = GetDuiHandle(dui)
    local txd = CreateRuntimeTxd(txdName)
    CreateRuntimeTextureFromDuiHandle(txd, txnName, handle)

    monitorDuis[key] = { dui = dui, txd = txdName, txn = txnName, group = group }
    return monitorDuis[key]
end

local function destroyMonitorDuis()
    for _, data in pairs(monitorDuis) do
        if data.dui then DestroyDui(data.dui) end
    end
    monitorDuis = {}
    monitorLastDuiPayload = {}
    monitorLastDuiSent = {}
end

local function sendMonitorDui(key, group, restaurantId, orders)
    local data = getMonitorDui(key, group)
    if not data or not data.dui then return end

    local restaurant = restaurants and restaurants[restaurantId] or nil
    local payloadTable = { view = group, restaurantId = restaurantId, orders = orders or {}, theme = restaurant and restaurant.theme or nil }
    local payload = json.encode(payloadTable)
    local now = GetGameTimer()

    -- Wichtig: DUI-Seiten sind beim Erstellen nicht sofort empfangsbereit.
    -- Deshalb senden wir identische Payloads regelmäßig erneut, statt sie komplett wegzudeduplizieren.
    if monitorLastDuiPayload[key] == payload and monitorLastDuiSent[key] and (now - monitorLastDuiSent[key]) < 1000 then return end
    monitorLastDuiPayload[key] = payload
    monitorLastDuiSent[key] = now
    SendDuiMessage(data.dui, json.encode({ action = 'tvDisplay', payload = payloadTable }))
end

local function rotatePoint(x, y, z, heading)
    local rad = math.rad(heading or 0.0)
    local right = vector3(math.cos(rad), math.sin(rad), 0.0)
    local forward = vector3(-math.sin(rad), math.cos(rad), 0.0)
    local up = vector3(0.0, 0.0, 1.0)
    return right * x + forward * y + up * z
end

local function monitorScreenConfig(point)
    local cfg = Config.MonitorLiveDisplay or {}
    local sizes = Config.MonitorSizes or {}
    local selected = point and sizes[point.screen_size or ''] or nil
    local drawBothSides = cfg.drawBothSides
    if selected and selected.drawBothSides ~= nil then drawBothSides = selected.drawBothSides end
    return {
        screenWidth = (selected and selected.screenWidth) or cfg.screenWidth or 1.18,
        screenHeight = (selected and selected.screenHeight) or cfg.screenHeight or 0.66,
        screenOffsetUp = (selected and selected.screenOffsetUp) or cfg.screenOffsetUp or 0.58,
        screenOffsetForward = (selected and selected.screenOffsetForward) or cfg.screenOffsetForward or 0.07,
        drawBothSides = drawBothSides
    }
end

local function monitorModel(pointType, screenSize, savedModel)
    local size = screenSize or ''
    local models = Config.MonitorModels or {}
    if models[size] and models[size][pointType] then return models[size][pointType] end
    if savedModel and savedModel ~= '' then return savedModel end
    return (Config.MonitorProps and Config.MonitorProps[pointType]) or 'prop_tv_flat_01'
end

local function drawDuiTvScreen(coords, heading, duiData, point)
    if not duiData then return end
    local cfg = monitorScreenConfig(point)
    local w = (cfg.screenWidth or 1.18) / 2.0
    local h = (cfg.screenHeight or 0.66) / 2.0

    local function drawAtOffset(offsetForward)
        local center = coords + rotatePoint(0.0, offsetForward, cfg.screenOffsetUp or 0.58, heading)
        local tl = center + rotatePoint(-w, 0.0, h, heading)
        local tr = center + rotatePoint(w, 0.0, h, heading)
        local bl = center + rotatePoint(-w, 0.0, -h, heading)
        local br = center + rotatePoint(w, 0.0, -h, heading)

        DrawSpritePoly(tl.x, tl.y, tl.z, bl.x, bl.y, bl.z, br.x, br.y, br.z, 255, 255, 255, 255, duiData.txd, duiData.txn, 0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0)
        DrawSpritePoly(tl.x, tl.y, tl.z, br.x, br.y, br.z, tr.x, tr.y, tr.z, 255, 255, 255, 255, duiData.txd, duiData.txn, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0)
    end

    -- Manche TV-Props haben die sichtbare Vorderseite je nach Heading/Model auf der anderen Seite.
    -- Deshalb rendern wir die DUI-Fläche standardmäßig auf beide Seiten des TV-Objekts.
    local off = cfg.screenOffsetForward or 0.07
    drawAtOffset(off)
    if cfg.drawBothSides ~= false then drawAtOffset(-off) end
end

refreshMonitorOrders = function(force)
    local now = GetGameTimer()
    local cfg = Config.MonitorLiveDisplay or {}
    if not force and now - monitorLastFetch < (cfg.refreshMs or 3000) then return end
    monitorLastFetch = now
    for restaurantId, restaurant in pairs(restaurants or {}) do
        local hasMonitor = false
        for _, group in ipairs({ 'kitchen', 'pickup' }) do
            if restaurant.points and restaurant.points[group] and #restaurant.points[group] > 0 then hasMonitor = true end
        end
        if hasMonitor then
            monitorFetchSerial[restaurantId] = (monitorFetchSerial[restaurantId] or 0) + 1
            local fetchSerial = monitorFetchSerial[restaurantId]
            serverCallback('ba_restaurant:getMonitorOrders', function(result)
                if monitorFetchSerial[restaurantId] ~= fetchSerial then return end
                handleMonitorSounds(restaurantId, result or { kitchen = {}, pickup = {} })
                monitorOrderCache[restaurantId] = result or { kitchen = {}, pickup = {} }
            end, restaurantId)
        end
    end
end

local function requestModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function drawHelp(lines)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(table.concat(lines, '\n'))
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function deleteMonitorProps()
    for _, obj in pairs(spawnedMonitorProps) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    spawnedMonitorProps = {}
    destroyMonitorDuis()
end

local function spawnMonitorProps()
    deleteMonitorProps()
    for _, restaurant in pairs(restaurants or {}) do
        for _, group in ipairs({ 'kitchen', 'pickup' }) do
            for _, point in ipairs((restaurant.points and restaurant.points[group]) or {}) do
                local model = monitorModel(group, point.screen_size, point.prop_model)
                local hash = requestModel(model)
                if hash then
                    local obj = CreateObject(hash, point.x, point.y, point.z, false, false, false)
                    SetEntityHeading(obj, point.heading or 0.0)
                    FreezeEntityPosition(obj, true)
                    SetEntityInvincible(obj, true)
                    SetEntityAsMissionEntity(obj, true, true)
                    spawnedMonitorProps[#spawnedMonitorProps + 1] = obj
                    SetModelAsNoLongerNeeded(hash)
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        local sleep = 1000
        if Config.MonitorLiveDisplay and Config.MonitorLiveDisplay.enabled then
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local drawDist = (Config.MonitorLiveDisplay and Config.MonitorLiveDisplay.drawDistance) or 18.0
            local nearAny = false
            for restaurantId, restaurant in pairs(restaurants or {}) do
                for _, group in ipairs({ 'kitchen', 'pickup' }) do
                    for _, point in ipairs((restaurant.points and restaurant.points[group]) or {}) do
                        local coords = vector3(point.x or point.coords.x, point.y or point.coords.y, point.z or point.coords.z)
                        local dist = #(playerCoords - coords)
                        if dist <= drawDist then
                            nearAny = true
                            sleep = 0
                            local cache = monitorOrderCache[restaurantId] or { kitchen = {}, pickup = {} }
                            local key = monitorKey(restaurantId, group, point)
                            local orders = cache[group] or {}
                            if Config.MonitorLiveDisplay.useDuiScreen then
                                sendMonitorDui(key, group, restaurantId, orders)
                                drawDuiTvScreen(coords, point.heading or 0.0, getMonitorDui(key, group), point)
                                if (Config.MonitorLiveDisplay.fallbackText == true) then
                                    drawMonitorBoard(coords, point.heading or 0.0, monitorLines(group, orders))
                                end
                            else
                                drawMonitorBoard(coords, point.heading or 0.0, monitorLines(group, orders))
                            end
                        end
                    end
                end
            end
            if nearAny then refreshMonitorOrders(false) end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        clearInteractionTargets()
        deleteMonitorProps()
    end
end)

RegisterNetEvent('ba_restaurant:restaurantsRefresh', function()
    Wait(250)
    spawnMonitorProps()
end)

CreateThread(function()
    Wait(2500)
    refreshRestaurants(function() spawnMonitorProps() end)
end)

local function startMonitorPlacement(data)
    local restaurantId = data and data.restaurantId
    local pointType = data and data.pointType
    local screenSize = data and data.screenSize
    local soundEnabled = data and data.soundEnabled
    local soundRange = data and data.soundRange
    local soundVolume = data and data.soundVolume
    if not restaurantId or (pointType ~= 'kitchen' and pointType ~= 'pickup') then return end

    SendNUIMessage({ action = 'forceClose' })
    resetNuiFocus()
    currentUi = nil
    appClosed = true

    local ped = PlayerPedId()
    local startCoords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.2, 0.0)
    local heading = GetEntityHeading(ped)
    local model = monitorModel(pointType, screenSize)
    local hash = requestModel(model)
    if not hash then notify('TV-Modell konnte nicht geladen werden: ' .. tostring(model), 'error') return end

    local obj = CreateObject(hash, startCoords.x, startCoords.y, startCoords.z, false, false, false)
    SetEntityHeading(obj, heading)
    FreezeEntityPosition(obj, true)
    SetEntityAlpha(obj, 210, false)
    SetEntityCollision(obj, false, false)
    SetEntityAsMissionEntity(obj, true, true)

    local coords = vector3(startCoords.x, startCoords.y, startCoords.z)
    local step = (Config.MonitorPlacement and Config.MonitorPlacement.moveStep) or 0.03
    local rotStep = (Config.MonitorPlacement and Config.MonitorPlacement.rotateStep) or 2.5
    local maxDist = (Config.MonitorPlacement and Config.MonitorPlacement.maxDistance) or 8.0

    while true do
        Wait(0)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        for _, control in ipairs({ 30, 31, 32, 33, 34, 35, 44, 38, 85, 172, 173, 174, 175, 188, 187 }) do
            DisableControlAction(0, control, true)
        end
        DisableControlAction(0, 177, true)
        drawHelp({
            '~y~TV-Monitor platzieren~s~',
            'W/S/A/D bewegen · Q/E oder Pfeil hoch/runter',
            'Pfeil links/rechts drehen · ~g~ENTER speichern~s~ · ~r~BACKSPACE abbrechen~s~'
        })

        local fwd = GetEntityForwardVector(obj)
        local right = vector3(fwd.y, -fwd.x, 0.0)
        if IsControlPressed(0, 32) or IsDisabledControlPressed(0, 32) then coords = coords + vector3(fwd.x, fwd.y, 0.0) * step end -- W
        if IsControlPressed(0, 33) or IsDisabledControlPressed(0, 33) then coords = coords - vector3(fwd.x, fwd.y, 0.0) * step end -- S
        if IsControlPressed(0, 34) or IsDisabledControlPressed(0, 34) then coords = coords - right * step end -- A
        if IsControlPressed(0, 35) or IsDisabledControlPressed(0, 35) then coords = coords + right * step end -- D
        if IsControlPressed(0, 44) or IsDisabledControlPressed(0, 44) or IsControlPressed(0, 172) or IsDisabledControlPressed(0, 172) then coords = coords + vector3(0.0, 0.0, step) end -- Q / Pfeil hoch
        if IsControlPressed(0, 38) or IsDisabledControlPressed(0, 38) or IsControlPressed(0, 173) or IsDisabledControlPressed(0, 173) then coords = coords - vector3(0.0, 0.0, step) end -- E / Pfeil runter
        if IsControlPressed(0, 174) or IsDisabledControlPressed(0, 174) then heading = heading - rotStep end
        if IsControlPressed(0, 175) or IsDisabledControlPressed(0, 175) then heading = heading + rotStep end

        local pedCoords = GetEntityCoords(ped)
        if #(coords - pedCoords) > maxDist then
            coords = pedCoords + (coords - pedCoords) / #(coords - pedCoords) * maxDist
        end

        SetEntityCoordsNoOffset(obj, coords.x, coords.y, coords.z, false, false, false)
        SetEntityHeading(obj, heading)

        if IsControlJustReleased(0, 191) then -- Enter
            DeleteEntity(obj)
            TriggerServerEvent('ba_restaurant:adminSavePoint', restaurantId, pointType, coords.x, coords.y, coords.z, heading, model, screenSize, soundEnabled, soundRange, soundVolume)
            notify('TV-Monitor gespeichert.', 'success')
            reopenCreator(restaurantId)
            break
        elseif IsControlJustReleased(0, 177) then -- Backspace
            DeleteEntity(obj)
            notify('TV-Platzierung abgebrochen.', 'info')
            reopenCreator(restaurantId)
            break
        end
    end
    SetModelAsNoLongerNeeded(hash)
end

RegisterNUICallback('placeMonitorTv', function(data, cb)
    cb({ ok = true })
    startMonitorPlacement(data)
end)
