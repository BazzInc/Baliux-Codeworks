local function openReceipt(metadata)
    metadata = metadata or {}
    if metadata.metadata then metadata = metadata.metadata end
    if metadata.info then metadata = metadata.info end
    if metadata.item and metadata.item.metadata then metadata = metadata.item.metadata end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', payload = metadata })
end

RegisterNetEvent('ba_restaurant_receipts:open', function(itemData, slotData)
    local metadata = {}
    if slotData and (slotData.metadata or slotData.info) then
        metadata = slotData.metadata or slotData.info
    elseif itemData and (itemData.metadata or itemData.info) then
        metadata = itemData.metadata or itemData.info
    elseif itemData then
        metadata = itemData
    end
    openReceipt(metadata)
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    cb({ ok = true })
end)
