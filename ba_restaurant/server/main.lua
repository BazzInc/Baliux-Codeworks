local Framework = BA.Framework.Detect()
local ESX = Framework.name == 'esx' and Framework.object or nil
local Restaurants = {}
local getCharacterName

local function refreshFramework()
    Framework = BA.Framework.Detect()
    ESX = Framework.name == 'esx' and Framework.object or nil
    return Framework, ESX
end

local function debugPrint(...)
    if Config.Debug then print('[ba_restaurant]', ...) end
end

local function sanitizeText(value, maxLen)
    value = tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #value > maxLen then value = value:sub(1, maxLen) end
    return value
end

local function sanitizeColor(value, fallback)
    value = sanitizeText(value, 16)
    if value:match('^#%x%x%x%x%x%x$') then return value end
    return fallback
end

local function normalizeTheme(theme)
    theme = type(theme) == 'table' and theme or {}
    return {
        primary = sanitizeColor(theme.primary, '#e85d3f'),
        accent = sanitizeColor(theme.accent, '#28c7b7'),
        background = sanitizeColor(theme.background, '#111827')
    }
end

local function decodeTheme(themeJson)
    if not themeJson or themeJson == '' then return normalizeTheme(nil) end
    local ok, theme = pcall(function() return json.decode(themeJson) end)
    if ok then return normalizeTheme(theme) end
    return normalizeTheme(nil)
end

local function slug(value)
    value = sanitizeText(value, 64):lower():gsub('%s+', '_'):gsub('[^%w_%-]', '')
    return value
end

local function notify(src, msg, ntype)
    TriggerClientEvent('ba_restaurant:notify', src, msg, ntype or 'info')
end

local function formatMoney(amount)
    return ('%s%.2f'):format(Config.Currency or '$', tonumber(amount or 0) or 0)
end

local function webhookEnabled(event)
    local cfg = Config.Webhooks or {}
    if cfg.enabled ~= true then return false end
    local events = cfg.events or {}
    if events[event] == false then return false end
    return true
end

local function getWebhookUrl(event)
    local cfg = Config.Webhooks or {}
    local urls = cfg.urls or {}
    return sanitizeText(urls[event] or urls.support or cfg.url, 512)
end

local function supportLog(event, title, description, fields, color)
    if not webhookEnabled(event) then return end
    local url = getWebhookUrl(event)
    if url == '' then return end

    local embedFields = {}
    for _, field in ipairs(fields or {}) do
        local name = sanitizeText(field.name, 256)
        local value = sanitizeText(field.value, 1024)
        if name ~= '' and value ~= '' then
            embedFields[#embedFields + 1] = {
                name = name,
                value = value,
                inline = field.inline ~= false
            }
        end
    end

    local payload = {
        username = sanitizeText((Config.Webhooks or {}).username or 'BA Restaurant', 80),
        embeds = {{
            title = sanitizeText(title, 256),
            description = sanitizeText(description, 2048),
            color = tonumber(color) or 16737792,
            fields = embedFields,
            footer = { text = os.date('%d.%m.%Y %H:%M:%S') }
        }}
    }

    local avatar = sanitizeText((Config.Webhooks or {}).avatar, 512)
    if avatar ~= '' then payload.avatar_url = avatar end

    PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function callback(name, cb)
    RegisterNetEvent(name, function(requestId, ...)
        local src = source
        cb(src, function(result) TriggerClientEvent(name .. ':response', src, requestId, result) end, ...)
    end)
end

local function isAdmin(src)
    if src == 0 then return Config.AdminCreator.allowConsole == true end
    if IsPlayerAceAllowed(src, Config.AdminCreator.ace or 'ba_restaurant.creator') then return true end
    if IsPlayerAceAllowed(src, 'command.' .. (Config.AdminCreator.command or 'restaurantcreator')) then return true end
    return false
end

local function getIdentifier(source)
    refreshFramework()
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        return xPlayer and xPlayer.identifier or ('source:' .. source)
    end
    return ('source:' .. source)
end

local function getPlayerCfxIdentifier(source)
    local fallback = ('source:%s'):format(tostring(source))
    if not source or source == 0 then return 'Konsole' end
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local identifier = GetPlayerIdentifier(source, i)
        if identifier and identifier:find('^fivem:') then return identifier:gsub('^fivem:', '') end
    end
    for i = 0, GetNumPlayerIdentifiers(source) - 1 do
        local identifier = GetPlayerIdentifier(source, i)
        if identifier and identifier:find('^license:') then return identifier end
    end
    return fallback
end

local function actorLogFields(source, label)
    label = sanitizeText(label or 'Ausgefuehrt von', 64)
    return {
        { name = label, value = getCharacterName(source) },
        { name = 'CFX Nummer', value = getPlayerCfxIdentifier(source) }
    }
end

function getCharacterName(source)
    refreshFramework()
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if xPlayer.getName then
                local name = ''
                pcall(function() name = sanitizeText(xPlayer.getName(), 128) end)
                if name == '' then pcall(function() name = sanitizeText(xPlayer.getName(xPlayer), 128) end) end
                if name ~= '' then return name end
            end
            local first, last = '', ''
            if xPlayer.get then
                pcall(function() first = sanitizeText(xPlayer.get('firstName'), 64) end)
                pcall(function() last = sanitizeText(xPlayer.get('lastName'), 64) end)
                if first == '' and last == '' then
                    pcall(function() first = sanitizeText(xPlayer.get(xPlayer, 'firstName'), 64) end)
                    pcall(function() last = sanitizeText(xPlayer.get(xPlayer, 'lastName'), 64) end)
                end
            end
            local full = sanitizeText((first .. ' ' .. last), 128)
            if full ~= '' then return full end
        end
    end
    local playerName = sanitizeText(GetPlayerName(source), 128)
    return playerName ~= '' and playerName or ('Spieler ' .. tostring(source))
end

local oxItemImageCache = nil
local function getOxItemImageSuggestions(query)
    query = sanitizeText(query, 64):lower()
    if #query < 2 then return {} end
    if not oxItemImageCache then
        oxItemImageCache = {}
        local raw = LoadResourceFile('ox_inventory', 'data/items.lua') or ''
        for name, block in raw:gmatch("%[%s*['\"]([^'\"]+)['\"]%s*%]%s*=%s*{(.-)\n%s*},") do
            local label = block:match("label%s*=%s*['\"]([^'\"]+)['\"]") or name
            local image = block:match("image%s*=%s*['\"]([^'\"]+)['\"]") or (name .. '.png')
            oxItemImageCache[#oxItemImageCache + 1] = {
                name = name,
                label = label,
                image = image,
                path = ('nui://ox_inventory/web/images/%s'):format(image)
            }
        end
    end
    local out = {}
    for _, item in ipairs(oxItemImageCache) do
        local haystack = (item.name .. ' ' .. item.label .. ' ' .. item.image):lower()
        if haystack:find(query, 1, true) then
            out[#out + 1] = item
            if #out >= 10 then break end
        end
    end
    return out
end

local function normalizeReceiptItems(items)
    local out = {}
    for _, item in ipairs(items or {}) do
        local amount = tonumber(item.amount or item.count or 1) or 1
        local price = tonumber(item.price or 0) or 0
        out[#out + 1] = {
            label = sanitizeText(item.label or item.name or 'Artikel', 128),
            amount = amount,
            price = price,
            total = price * amount,
            type = item.menu_id and 'menu' or 'product',
            product_id = item.product_id,
            menu_id = item.menu_id
        }
    end
    return out
end

local function formatOrderLines(items)
    local textLines = {}
    for _, item in ipairs(normalizeReceiptItems(items)) do
        textLines[#textLines + 1] = (('%sx %s - %s%s'):format(item.amount or 1, item.label or 'Artikel', Config.Currency or '$', string.format('%.2f', tonumber(item.total or 0))))
    end
    return table.concat(textLines, '\n')
end

local function buildReceiptItemList(items)
    return normalizeReceiptItems(items)
end

local function giveOrderPaper(src, orderNumber, restaurantLabel, total, items, paperType, paymentText, paymentMethod, orderId, tipAmount, subtotal)
    -- Zentrale Stelle für ox_inventory-Metadaten.
    -- Wichtig: Hier wird NICHT mehr aus irgendeinem alten Fallback geraten, sondern der übergebene paperType entscheidet eindeutig:
    --   note    = unbezahlter Bestellzettel
    --   receipt = bezahlter Kassenbon
    local isReceipt = paperType == 'receipt'
    local itemName = isReceipt and (Config.ReceiptItem or Config.CashReceiptItem or 'restaurant_receipt') or (Config.OrderNoteItem or Config.OrderPaperItem or 'restaurant_order_note')
    if isReceipt and Config.GiveCashReceiptItem == false then return end
    if not isReceipt and Config.GiveOrderPaperItem == false then return end
    if not itemName or itemName == '' then return end

    refreshFramework()
    local now = os.date('%d.%m.%Y %H:%M:%S')
    local receiptItems = normalizeReceiptItems(items)
    local itemCount = 0
    for _, entry in ipairs(receiptItems) do itemCount = itemCount + (tonumber(entry.amount) or 1) end

    local method = tostring(paymentMethod or (isReceipt and 'card' or 'cash')):lower()
    if method ~= 'cash' and method ~= 'card' then method = isReceipt and 'card' or 'cash' end

    local statusText
    local statusCode
    if isReceipt then
        statusCode = method == 'cash' and 'paid_cash' or 'paid_card'
        statusText = paymentText or (method == 'cash' and 'Bar bezahlt' or 'Mit Karte bezahlt')
    else
        statusCode = 'pending_cash'
        statusText = 'Noch nicht bezahlt'
        method = 'cash'
    end

    local restaurantName = sanitizeText(restaurantLabel, 128)
    if restaurantName == '' then restaurantName = 'Unbekanntes Restaurant' end

    tipAmount = math.max(0, tonumber(tipAmount) or 0)
    subtotal = tonumber(subtotal) or (tonumber(total or 0) - tipAmount)
    if subtotal < 0 then subtotal = 0 end

    local title = isReceipt and ('Kassenbon #%s'):format(orderNumber) or ('Bestellzettel #%s'):format(orderNumber)
    local lines = formatOrderLines(receiptItems)
    local meta = {
        -- ox_inventory Standard-Anzeige
        label = title,
        title = title,
        type = itemName,
        description = ('%s | Bestellung #%s | %s%.2f | %s | %s Position(en)'):format(restaurantName, tostring(orderNumber), Config.Currency or '$', tonumber(total or 0), statusText, itemCount),

        -- stabile Felder für die eigene Bon-UI
        order_id = orderId,
        order_number = tonumber(orderNumber) or orderNumber,
        orderNumber = tonumber(orderNumber) or orderNumber,
        restaurant = restaurantName,
        restaurant_name = restaurantName,
        total = tonumber(total or 0),
        subtotal = subtotal,
        tip_amount = tipAmount,
        tip = tipAmount,
        currency = Config.Currency or '$',
        payment = statusText,
        payment_text = statusText,
        payment_label = statusText,
        payment_method = method,
        payment_status = statusCode,
        status_label = statusText,
        paid = isReceipt and true or false,
        is_paid = isReceipt and 1 or 0,
        paid_status = isReceipt and 'paid' or 'unpaid',
        receipt_type = isReceipt and 'receipt' or 'note',
        note_type = isReceipt and 'receipt' or 'order_note',
        created_at = now,
        time = now,
        item_count = itemCount,
        positions_count = #receiptItems,
        items_text = lines,
        items_json = json.encode(receiptItems),
        items = receiptItems
    }

    -- Extra flache Positionsfelder, falls ein Inventory/Bridge verschachtelte Tabellen nicht sauber an die Client-Eventdaten gibt.
    for i, entry in ipairs(receiptItems) do
        if i > 20 then break end
        meta['item_' .. i .. '_label'] = entry.label
        meta['item_' .. i .. '_amount'] = entry.amount
        meta['item_' .. i .. '_price'] = entry.price
        meta['item_' .. i .. '_total'] = entry.total
    end

    if GetResourceState('ox_inventory') == 'started' then
        local ok, err = exports.ox_inventory:AddItem(src, itemName, 1, meta)
        if not ok then
            supportLog('errors', 'Inventar-Ausgabe fehlgeschlagen', 'Ein Bestellzettel oder Kassenbon konnte nicht ins Inventar gelegt werden.', {
                { name = 'Restaurant', value = restaurantName },
                { name = 'Bestellung', value = '#' .. tostring(orderNumber) },
                { name = 'Item', value = tostring(itemName) },
                { name = 'Fehler', value = tostring(err), inline = false }
            }, 15158332)
            notify(src, ('%s konnte nicht ins Inventar gelegt werden.'):format(isReceipt and 'Kassenbon' or 'Bestellzettel'), 'error')
        end
        return
    end

    if ESX then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer and xPlayer.addInventoryItem then
            xPlayer.addInventoryItem(itemName, 1)
        end
    end
end

local function giveOrderNote(src, orderNumber, restaurantLabel, total, items, orderId, tipAmount, subtotal)
    giveOrderPaper(src, orderNumber, restaurantLabel, total, items, 'note', 'Noch nicht bezahlt', 'cash', orderId, tipAmount, subtotal)
end

local function givePaidReceipt(src, orderNumber, restaurantLabel, total, items, paymentText, paymentMethod, orderId, tipAmount, subtotal)
    paymentMethod = paymentMethod or (paymentText == 'Bar bezahlt' and 'cash' or 'card')
    giveOrderPaper(src, orderNumber, restaurantLabel, total, items, 'receipt', paymentText, paymentMethod, orderId, tipAmount, subtotal)
end

local function getJobData(source)
    refreshFramework()
    if not ESX then return nil end
    local xPlayer = ESX.GetPlayerFromId(source)
    return xPlayer and xPlayer.job or nil
end

local function getRestaurant(restaurantId)
    return Restaurants[restaurantId] or (Config.Restaurants and Config.Restaurants[restaurantId])
end

local function getSocietyAccountName(restaurant)
    local account = sanitizeText(restaurant and (restaurant.societyAccount or restaurant.society_account), 128)
    if account ~= '' then return account end
    local job = sanitizeText(restaurant and restaurant.job, 64)
    if job ~= '' then return 'society_' .. job end
    return ''
end

local function getSqlSocietyAccount(accountName)
    accountName = sanitizeText(accountName, 128)
    if accountName == '' then return nil end

    local ok = pcall(function()
        MySQL.insert.await('INSERT IGNORE INTO addon_account (name, label, shared) VALUES (?, ?, 1)', { accountName, accountName:gsub('^society_', '') })
    end)
    if not ok then
        supportLog('errors', 'Fraktionskonto konnte nicht vorbereitet werden', 'addon_account konnte nicht geprueft oder angelegt werden.', {
            { name = 'Konto', value = accountName }
        }, 15158332)
        return nil
    end

    local exists = MySQL.scalar.await('SELECT COUNT(*) FROM addon_account WHERE name = ?', { accountName }) or 0
    if tonumber(exists) < 1 then
        supportLog('errors', 'Fraktionskonto fehlt', 'Das Konto wurde in addon_account nicht gefunden.', {
            { name = 'Konto', value = accountName }
        }, 15158332)
        return nil
    end

    pcall(function()
        local dataRows = MySQL.scalar.await("SELECT COUNT(*) FROM addon_account_data WHERE account_name = ? AND (owner IS NULL OR owner = '')", { accountName }) or 0
        if tonumber(dataRows) < 1 then
            local inserted = pcall(function()
                MySQL.insert.await('INSERT INTO addon_account_data (account_name, money, owner) VALUES (?, 0, NULL)', { accountName })
            end)
            if not inserted then
                pcall(function() MySQL.insert.await("INSERT INTO addon_account_data (account_name, money, owner) VALUES (?, 0, '')", { accountName }) end)
            end
        end
    end)

    return {
        name = accountName,
        addMoney = function(amount)
            amount = tonumber(amount) or 0
            local affected = MySQL.update.await("UPDATE addon_account_data SET money = money + ? WHERE account_name = ? AND (owner IS NULL OR owner = '')", { amount, accountName }) or 0
            if affected < 1 then
                affected = MySQL.update.await("UPDATE addon_account_data SET money = money + ? WHERE account_name = ?", { amount, accountName }) or 0
            end
            if affected < 1 then
                local inserted = pcall(function()
                    MySQL.insert.await('INSERT INTO addon_account_data (account_name, money, owner) VALUES (?, ?, NULL)', { accountName, amount })
                end)
                if not inserted then
                    pcall(function() MySQL.insert.await("INSERT INTO addon_account_data (account_name, money, owner) VALUES (?, ?, '')", { accountName, amount }) end)
                end
            end
        end
    }
end

local function getSharedSocietyAccount(accountName)
    accountName = sanitizeText(accountName, 128)
    if accountName == '' then return nil end
    if GetResourceState('esx_addonaccount') ~= 'started' then
        return getSqlSocietyAccount(accountName)
    end
    local done, account = false, nil
    TriggerEvent('esx_addonaccount:getSharedAccount', accountName, function(result)
        account = result
        done = true
    end)
    local timeout = GetGameTimer() + 1000
    while not done and GetGameTimer() < timeout do Wait(0) end
    if account and account.addMoney then return account end
    return getSqlSocietyAccount(accountName)
end

local function hasRestaurantJob(source, restaurantId)
    local restaurant = getRestaurant(restaurantId)
    if not restaurant then return false end
    refreshFramework()
    if not ESX then return false end
    local job = getJobData(source)
    return job and job.name == restaurant.job
end

local function hasManagementAccess(source, restaurantId, includeAdmin)
    if includeAdmin ~= false and isAdmin(source) then return true end
    local restaurant = getRestaurant(restaurantId)
    if not restaurant then return false end
    refreshFramework()
    if not ESX then return true end
    local job = getJobData(source)
    if not job or job.name ~= restaurant.job then return false end
    local management = Config.Management or {}
    if management.requireBoss == false then return true end
    local allowedGrades = restaurant.managementGrades or management.allowedGrades or { boss = true, owner = true }
    local gradeName = tostring(job.grade_name or ''):lower()
    if allowedGrades[gradeName] then return true end
    local minGrade = restaurant.managementMinGrade or management.minGrade
    if minGrade and tonumber(job.grade or -1) >= tonumber(minGrade) then return true end
    return false
end

local function getRestaurantPermissions(source, restaurantId)
    local admin = isAdmin(source)
    local employee = hasRestaurantJob(source, restaurantId)
    local boss = hasManagementAccess(source, restaurantId, false)
    return { admin = admin, employee = employee, boss = boss }
end

local function canOpenPoint(source, restaurantId, view)
    if view == 'terminal' or view == 'pickup' then return true end
    if view == 'manager' then return hasManagementAccess(source, restaurantId) end
    if view == 'kitchen' or view == 'cashier' then return hasRestaurantJob(source, restaurantId) end
    return false
end

local function ensureSchema()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ba_restaurants` (
      `id` varchar(64) NOT NULL,
      `label` varchar(128) NOT NULL,
      `job` varchar(64) NOT NULL,
      `society_account` varchar(128) DEFAULT NULL,
      `theme_json` longtext DEFAULT NULL,
      `enabled` tinyint(1) NOT NULL DEFAULT 1,
      `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ba_restaurant_points` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `restaurant_id` varchar(64) NOT NULL,
      `point_type` varchar(32) NOT NULL,
      `label` varchar(128) DEFAULT NULL,
      `x` double NOT NULL,
      `y` double NOT NULL,
      `z` double NOT NULL,
      `heading` double NOT NULL DEFAULT 0,
      `prop_model` varchar(96) DEFAULT NULL,
      `screen_size` varchar(32) DEFAULT NULL,
      `sound_enabled` tinyint(1) DEFAULT NULL,
      `sound_range` double DEFAULT NULL,
      `sound_volume` double DEFAULT NULL,
      `enabled` tinyint(1) NOT NULL DEFAULT 1,
      PRIMARY KEY (`id`), KEY `restaurant_id` (`restaurant_id`), KEY `point_type` (`point_type`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ba_restaurant_categories` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `restaurant_id` varchar(64) NOT NULL,
      `name` varchar(64) NOT NULL,
      `label` varchar(128) NOT NULL,
      `icon` varchar(16) DEFAULT NULL,
      `image` varchar(512) DEFAULT NULL,
      `sort_order` int(11) NOT NULL DEFAULT 1,
      `enabled` tinyint(1) NOT NULL DEFAULT 1,
      PRIMARY KEY (`id`), KEY `restaurant_id` (`restaurant_id`), UNIQUE KEY `restaurant_category_name` (`restaurant_id`,`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ba_restaurant_products` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `restaurant_id` varchar(64) NOT NULL,
      `category` varchar(64) NOT NULL,
      `label` varchar(128) NOT NULL,
      `description` text DEFAULT NULL,
      `price` decimal(10,2) NOT NULL DEFAULT 0.00,
      `item_name` varchar(128) DEFAULT NULL,
      `image` varchar(512) DEFAULT NULL,
      `enabled` tinyint(1) NOT NULL DEFAULT 1,
      `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `restaurant_id` (`restaurant_id`), KEY `category` (`category`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ba_restaurant_menus` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `restaurant_id` varchar(64) NOT NULL,
      `label` varchar(128) NOT NULL,
      `description` text DEFAULT NULL,
      `price` decimal(10,2) NOT NULL DEFAULT 0.00,
      `products_json` longtext NOT NULL,
      `enabled` tinyint(1) NOT NULL DEFAULT 1,
      `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `restaurant_id` (`restaurant_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ba_restaurant_orders` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `restaurant_id` varchar(64) NOT NULL,
      `order_number` int(11) NOT NULL,
      `customer_identifier` varchar(128) DEFAULT NULL,
      `status` varchar(32) NOT NULL DEFAULT 'open',
      `payment_method` varchar(32) NOT NULL DEFAULT 'card',
      `payment_status` varchar(32) NOT NULL DEFAULT 'pending',
      `subtotal` decimal(10,2) NOT NULL DEFAULT 0.00,
      `tip_amount` decimal(10,2) NOT NULL DEFAULT 0.00,
      `total` decimal(10,2) NOT NULL DEFAULT 0.00,
      `items_json` longtext NOT NULL,
      `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
      `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`), KEY `restaurant_id` (`restaurant_id`), KEY `order_number` (`order_number`), KEY `status` (`status`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ba_restaurant_payments` (
      `id` int(11) NOT NULL AUTO_INCREMENT,
      `restaurant_id` varchar(64) NOT NULL,
      `order_id` int(11) DEFAULT NULL,
      `order_number` int(11) DEFAULT NULL,
      `method` varchar(32) NOT NULL,
      `status` varchar(32) NOT NULL DEFAULT 'booked',
      `amount` decimal(10,2) NOT NULL DEFAULT 0.00,
      `tip_amount` decimal(10,2) NOT NULL DEFAULT 0.00,
      `society_account` varchar(128) DEFAULT NULL,
      `cashier_identifier` varchar(128) DEFAULT NULL,
      `cashier_name` varchar(128) DEFAULT NULL,
      `booked_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (`id`),
      KEY `restaurant_id` (`restaurant_id`),
      KEY `order_id` (`order_id`),
      KEY `method` (`method`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;]])

    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_products MODIFY COLUMN image varchar(512) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_products ADD COLUMN item_name varchar(128) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_products ADD COLUMN image varchar(512) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_categories ADD COLUMN icon varchar(16) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_categories ADD COLUMN image varchar(512) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_points ADD COLUMN prop_model varchar(96) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_points ADD COLUMN screen_size varchar(32) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_points ADD COLUMN sound_enabled tinyint(1) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_points ADD COLUMN sound_range double DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_points ADD COLUMN sound_volume double DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_orders ADD COLUMN cashier_identifier varchar(128) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_orders ADD COLUMN cashier_name varchar(128) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_orders ADD COLUMN subtotal decimal(10,2) NOT NULL DEFAULT 0.00') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_orders ADD COLUMN tip_amount decimal(10,2) NOT NULL DEFAULT 0.00') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_orders ADD COLUMN paid_at timestamp NULL DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_orders ADD COLUMN cash_closed_at timestamp NULL DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_orders ADD COLUMN cash_closed_by varchar(128) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_orders ADD COLUMN cash_closed_by_name varchar(128) DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurants ADD COLUMN theme_json longtext DEFAULT NULL') end)
    pcall(function() MySQL.query.await('ALTER TABLE ba_restaurant_payments ADD COLUMN tip_amount decimal(10,2) NOT NULL DEFAULT 0.00') end)
end

local function logPayment(restaurantId, orderId, orderNumber, method, amount, societyAccount, cashierIdentifier, cashierName, tipAmount)
    MySQL.insert.await([[INSERT INTO ba_restaurant_payments
        (restaurant_id, order_id, order_number, method, status, amount, tip_amount, society_account, cashier_identifier, cashier_name)
        VALUES (?, ?, ?, ?, 'booked', ?, ?, ?, ?, ?)]], {
        slug(restaurantId), tonumber(orderId), tonumber(orderNumber), sanitizeText(method, 32), tonumber(amount) or 0,
        math.max(0, tonumber(tipAmount) or 0), sanitizeText(societyAccount, 128), sanitizeText(cashierIdentifier, 128), sanitizeText(cashierName, 128)
    })
end

local function seedExampleRestaurants()
    local examples = {
        {
            id = 'burgershot',
            label = 'Burger Shot',
            job = 'burgershot',
            society = 'society_burgershot',
            theme = { primary = '#ff6a3d', accent = '#31d3c5', background = '#151018' },
            categories = {
                { name = 'burger', label = 'Burger', icon = 'B', sort = 1 },
                { name = 'drinks', label = 'Getraenke', icon = 'D', sort = 2 }
            },
            products = {
                { category = 'burger', label = 'Classic Burger', price = 12.50, item = 'burger', image = 'nui://ox_inventory/web/images/burger.png' },
                { category = 'drinks', label = 'Cola', price = 4.00, item = 'cola', image = 'nui://ox_inventory/web/images/cola.png' }
            }
        },
        {
            id = 'johnnys_diner',
            label = 'Johnnys Diner',
            job = 'johnnys_diner',
            society = 'society_johnnys_diner',
            theme = { primary = '#d84f45', accent = '#f4c542', background = '#12202a' },
            categories = {
                { name = 'mains', label = 'Speisen', icon = 'S', sort = 1 },
                { name = 'drinks', label = 'Getraenke', icon = 'D', sort = 2 }
            },
            products = {
                { category = 'mains', label = 'Diner Sandwich', price = 10.50, item = 'sandwich', image = 'nui://ox_inventory/web/images/sandwich.png' },
                { category = 'drinks', label = 'Kaffee', price = 3.50, item = 'coffee', image = 'nui://ox_inventory/web/images/coffee.png' }
            }
        }
    }

    for _, r in ipairs(examples) do
        MySQL.update.await([[INSERT IGNORE INTO ba_restaurants (id, label, job, society_account, theme_json, enabled) VALUES (?, ?, ?, ?, ?, 1)]], {
            r.id, r.label, r.job, r.society, json.encode(r.theme)
        })
        for _, c in ipairs(r.categories) do
            MySQL.update.await([[INSERT IGNORE INTO ba_restaurant_categories (restaurant_id, name, label, icon, image, sort_order, enabled) VALUES (?, ?, ?, ?, '', ?, 1)]], {
                r.id, c.name, c.label, c.icon, c.sort
            })
        end
        local productCount = MySQL.scalar.await('SELECT COUNT(*) FROM ba_restaurant_products WHERE restaurant_id = ?', { r.id }) or 0
        if tonumber(productCount) == 0 then
            for _, p in ipairs(r.products) do
                MySQL.insert.await([[INSERT INTO ba_restaurant_products (restaurant_id, category, label, description, price, item_name, image, enabled) VALUES (?, ?, ?, '', ?, ?, ?, 1)]], {
                    r.id, p.category, p.label, p.price, p.item, p.image
                })
            end
        end
    end
end

local function loadRestaurants(includeDisabled)
    local out = {}
    if not includeDisabled then
        for id, cfg in pairs(Config.Restaurants or {}) do
            out[id] = cfg
        end
    end

    local rows = MySQL.query.await(('SELECT * FROM ba_restaurants %s ORDER BY enabled DESC, label ASC'):format(includeDisabled and '' or 'WHERE enabled = 1')) or {}
    for _, r in ipairs(rows) do
        out[r.id] = {
            id = r.id,
            label = r.label,
            job = r.job,
            societyAccount = r.society_account,
            enabled = tonumber(r.enabled) == 1,
            theme = decodeTheme(r.theme_json),
            points = { terminals = {}, manager = {}, kitchen = {}, pickup = {}, cashier = {} }
        }
    end

    local points = MySQL.query.await('SELECT * FROM ba_restaurant_points WHERE enabled = 1 ORDER BY id ASC') or {}
    for _, p in ipairs(points) do
        local r = out[p.restaurant_id]
        if r then
            r.points = r.points or { terminals = {}, manager = {}, kitchen = {}, pickup = {}, cashier = {} }
            r.points[p.point_type] = r.points[p.point_type] or {}
            table.insert(r.points[p.point_type], { id = p.id, x = p.x, y = p.y, z = p.z, heading = p.heading, label = p.label, point_type = p.point_type, prop_model = p.prop_model, screen_size = p.screen_size, sound_enabled = p.sound_enabled, sound_range = p.sound_range, sound_volume = p.sound_volume, enabled = tonumber(p.enabled) == 1 })
        end
    end

    if not includeDisabled then Restaurants = out end
    return out
end

CreateThread(function()
    Wait(1000)
    ensureSchema()
    seedExampleRestaurants()
    refreshFramework()
    loadRestaurants()
    debugPrint(('Wurde gestartet. ba_core hat %s uebergeben.'):format(Framework.name or 'kein Framework'))
end)

RegisterCommand(Config.AdminCreator.command or 'restaurantcreator', function(src)
    if src == 0 then print('Der Restaurant-Creator ist nur ingame nutzbar.') return end
    if not isAdmin(src) then notify(src, 'Keine Admin-Berechtigung für den Restaurant-Creator.', 'error') return end
    TriggerClientEvent('ba_restaurant:openCreator', src)
end, false)

callback('ba_restaurant:getRestaurants', function(source, cb)
    local data = loadRestaurants()
    for restaurantId, restaurant in pairs(data) do
        restaurant.permissions = getRestaurantPermissions(source, restaurantId)
    end
    cb(data)
end)

callback('ba_restaurant:getAdminData', function(source, cb)
    if not isAdmin(source) then cb({ ok = false, error = 'Keine Admin-Berechtigung.' }) return end
    cb({ ok = true, restaurants = loadRestaurants(true), currency = Config.Currency })
end)

callback('ba_restaurant:searchOxInventoryImages', function(source, cb, query)
    cb(getOxItemImageSuggestions(query))
end)

RegisterNetEvent('ba_restaurant:adminSaveRestaurant', function(data)
    local src = source
    if not isAdmin(src) then notify(src, 'Keine Berechtigung.', 'error') return end
    if type(data) ~= 'table' then return end
    local id = slug(data.id ~= '' and data.id or data.label)
    local label = sanitizeText(data.label, 128)
    local job = slug(data.job)
    local society = sanitizeText(data.societyAccount or data.society_account, 128)
    local theme = normalizeTheme(data.theme)
    if id == '' or label == '' or job == '' then notify(src, 'Restaurant braucht ID, Name und Job.', 'error') return end
    MySQL.update.await([[INSERT INTO ba_restaurants (id, label, job, society_account, theme_json, enabled) VALUES (?, ?, ?, ?, ?, 1)
        ON DUPLICATE KEY UPDATE label = VALUES(label), job = VALUES(job), society_account = VALUES(society_account), theme_json = VALUES(theme_json), enabled = 1]], { id, label, job, society, json.encode(theme) })
    loadRestaurants()
    notify(src, 'Restaurant gespeichert.', 'success')
    TriggerClientEvent('ba_restaurant:restaurantsRefresh', -1)
end)

RegisterNetEvent('ba_restaurant:adminDeleteRestaurant', function(restaurantId)
    local src = source
    if not isAdmin(src) then notify(src, 'Keine Berechtigung.', 'error') return end
    restaurantId = slug(restaurantId)
    MySQL.update.await('UPDATE ba_restaurants SET enabled = 0 WHERE id = ?', { restaurantId })
    loadRestaurants()
    notify(src, 'Restaurant deaktiviert.', 'success')
    TriggerClientEvent('ba_restaurant:restaurantsRefresh', -1)
end)

RegisterNetEvent('ba_restaurant:adminHardDeleteRestaurant', function(data)
    local src = source
    if not isAdmin(src) then notify(src, 'Keine Berechtigung.', 'error') return end
    if type(data) ~= 'table' or data.confirm ~= true then notify(src, 'Löschen nicht bestätigt.', 'error') return end
    local restaurantId = slug(data.restaurantId)
    local enabled = MySQL.scalar.await('SELECT enabled FROM ba_restaurants WHERE id = ?', { restaurantId })
    if enabled == nil then notify(src, 'Restaurant nicht gefunden.', 'error') return end
    if tonumber(enabled) == 1 then notify(src, 'Restaurant erst deaktivieren, dann löschen.', 'error') return end
    MySQL.update.await('DELETE FROM ba_restaurant_points WHERE restaurant_id = ?', { restaurantId })
    MySQL.update.await('DELETE FROM ba_restaurant_categories WHERE restaurant_id = ?', { restaurantId })
    MySQL.update.await('DELETE FROM ba_restaurant_products WHERE restaurant_id = ?', { restaurantId })
    MySQL.update.await('DELETE FROM ba_restaurant_menus WHERE restaurant_id = ?', { restaurantId })
    MySQL.update.await('DELETE FROM ba_restaurant_payments WHERE restaurant_id = ?', { restaurantId })
    MySQL.update.await('DELETE FROM ba_restaurant_orders WHERE restaurant_id = ?', { restaurantId })
    MySQL.update.await('DELETE FROM ba_restaurants WHERE id = ?', { restaurantId })
    loadRestaurants()
    notify(src, 'Restaurant endgültig gelöscht.', 'success')
    TriggerClientEvent('ba_restaurant:restaurantsRefresh', -1)
end)

local function normalizeSoundSettings(pointType, soundEnabled, soundRange, soundVolume)
    if pointType ~= 'kitchen' and pointType ~= 'pickup' then return nil, nil, nil end
    local enabled = soundEnabled == true and 1 or 0
    local range = tonumber(soundRange)
    if not range or range < 1.0 then range = 18.0 end
    local volume = tonumber(soundVolume)
    if not volume then volume = 0.8 end
    if volume < 0.0 then volume = 0.0 end
    if volume > 1.0 then volume = 1.0 end
    return enabled, range, volume
end

RegisterNetEvent('ba_restaurant:adminSavePoint', function(restaurantId, pointType, x, y, z, heading, propModel, screenSize, soundEnabled, soundRange, soundVolume)
    local src = source
    if not isAdmin(src) then notify(src, 'Keine Berechtigung.', 'error') return end
    restaurantId = slug(restaurantId)
    pointType = sanitizeText(pointType, 32)
    local labels = { terminals = 'Selbstbestellterminal', manager = 'Manager-Laptop', kitchen = 'Küchenmonitor', pickup = 'Abholmonitor', cashier = 'Kasse' }
    if not getRestaurant(restaurantId) then notify(src, 'Restaurant existiert nicht.', 'error') return end
    if not labels[pointType] then notify(src, 'Ungültiger Punkt-Typ.', 'error') return end
    propModel = sanitizeText(propModel or ((Config.MonitorProps or {})[pointType]) or '', 96)
    if propModel == '' then propModel = nil end
    screenSize = sanitizeText(screenSize, 32)
    if screenSize ~= 'small' and screenSize ~= 'large' then screenSize = nil end
    local soundEnabledValue, soundRangeValue, soundVolumeValue = normalizeSoundSettings(pointType, soundEnabled, soundRange, soundVolume)
    MySQL.insert.await('INSERT INTO ba_restaurant_points (restaurant_id, point_type, label, x, y, z, heading, prop_model, screen_size, sound_enabled, sound_range, sound_volume, enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)', {
        restaurantId, pointType, labels[pointType], tonumber(x), tonumber(y), tonumber(z), tonumber(heading) or 0, propModel, screenSize, soundEnabledValue, soundRangeValue, soundVolumeValue
    })
    loadRestaurants()
    notify(src, labels[pointType] .. ' gesetzt.', 'success')
    TriggerClientEvent('ba_restaurant:restaurantsRefresh', -1)
end)

RegisterNetEvent('ba_restaurant:adminUpdatePointSound', function(data)
    local src = source
    if not isAdmin(src) then notify(src, 'Keine Berechtigung.', 'error') return end
    if type(data) ~= 'table' then return end
    local id = tonumber(data.id)
    local restaurantId = slug(data.restaurantId)
    if not id or restaurantId == '' then return end
    local point = MySQL.single.await('SELECT id, point_type FROM ba_restaurant_points WHERE id = ? AND restaurant_id = ? AND enabled = 1', { id, restaurantId })
    if not point or (point.point_type ~= 'kitchen' and point.point_type ~= 'pickup') then notify(src, 'Monitorpunkt nicht gefunden.', 'error') return end
    local soundEnabledValue, soundRangeValue, soundVolumeValue = normalizeSoundSettings(point.point_type, data.soundEnabled, data.soundRange, data.soundVolume)
    MySQL.update.await('UPDATE ba_restaurant_points SET sound_enabled = ?, sound_range = ?, sound_volume = ? WHERE id = ? AND restaurant_id = ?', { soundEnabledValue, soundRangeValue, soundVolumeValue, id, restaurantId })
    loadRestaurants()
    notify(src, 'Monitor-Sound gespeichert.', 'success')
    TriggerClientEvent('ba_restaurant:restaurantsRefresh', -1)
end)

RegisterNetEvent('ba_restaurant:adminDeletePoint', function(id)
    local src = source
    if not isAdmin(src) then notify(src, 'Keine Berechtigung.', 'error') return end
    MySQL.update.await('UPDATE ba_restaurant_points SET enabled = 0 WHERE id = ?', { tonumber(id) })
    loadRestaurants()
    notify(src, 'Punkt entfernt.', 'success')
    TriggerClientEvent('ba_restaurant:restaurantsRefresh', -1)
end)

callback('ba_restaurant:getMenu', function(_, cb, restaurantId)
    restaurantId = slug(restaurantId)
    local restaurant = getRestaurant(restaurantId)
    if not restaurant then cb(nil) return end
    local categories = MySQL.query.await('SELECT id, name, label, icon, image, sort_order, enabled FROM ba_restaurant_categories WHERE restaurant_id = ? AND enabled = 1 ORDER BY sort_order ASC, id ASC', { restaurantId })
    local products = MySQL.query.await([[SELECT p.id, p.category, c.label AS category_label, p.label, p.description, p.price, p.item_name, p.image, p.enabled FROM ba_restaurant_products p LEFT JOIN ba_restaurant_categories c ON c.restaurant_id = p.restaurant_id AND c.name = p.category WHERE p.restaurant_id = ? AND p.enabled = 1 ORDER BY p.category ASC, p.id ASC]], { restaurantId })
    local menus = MySQL.query.await('SELECT * FROM ba_restaurant_menus WHERE restaurant_id = ? AND enabled = 1 ORDER BY id ASC', { restaurantId })
    cb({ restaurant = restaurant.label, categories = categories or {}, products = products or {}, menus = menus or {}, currency = Config.Currency, theme = restaurant.theme, tips = Config.Tips or { enabled = true, presets = { 10, 20, 30 } } })
end)

callback('ba_restaurant:getManagerData', function(source, cb, restaurantId)
    restaurantId = slug(restaurantId)
    local restaurant = getRestaurant(restaurantId)
    if not restaurant then cb({ ok = false, error = 'Restaurant nicht gefunden.' }) return end
    if not hasManagementAccess(source, restaurantId) then cb({ ok = false, error = 'Nur Boss/Inhaber/Manager darf Produkte verwalten.' }) return end
    local categories = MySQL.query.await('SELECT * FROM ba_restaurant_categories WHERE restaurant_id = ? ORDER BY sort_order ASC, id ASC', { restaurantId })
    local products = MySQL.query.await('SELECT * FROM ba_restaurant_products WHERE restaurant_id = ? ORDER BY category ASC, id ASC', { restaurantId })
    local menus = MySQL.query.await('SELECT * FROM ba_restaurant_menus WHERE restaurant_id = ? ORDER BY id ASC', { restaurantId })
    local cashTotalToday = MySQL.scalar.await([[SELECT COALESCE(SUM(total),0) FROM ba_restaurant_orders WHERE restaurant_id = ? AND payment_method = 'cash' AND payment_status = 'paid_cash' AND DATE(COALESCE(paid_at, updated_at)) = CURDATE()]], { restaurantId }) or 0
    local cashTotalOpen = MySQL.scalar.await([[SELECT COALESCE(SUM(total),0) FROM ba_restaurant_orders WHERE restaurant_id = ? AND payment_method = 'cash' AND payment_status = 'paid_cash' AND cash_closed_at IS NULL]], { restaurantId }) or 0
    local cashTotalAll = MySQL.scalar.await([[SELECT COALESCE(SUM(total),0) FROM ba_restaurant_orders WHERE restaurant_id = ? AND payment_method = 'cash' AND payment_status = 'paid_cash']], { restaurantId }) or 0
    local cardToday = MySQL.scalar.await([[SELECT COALESCE(SUM(amount),0) FROM ba_restaurant_payments WHERE restaurant_id = ? AND method = 'card' AND DATE(booked_at) = CURDATE()]], { restaurantId }) or 0
    local cardTotal = MySQL.scalar.await([[SELECT COALESCE(SUM(amount),0) FROM ba_restaurant_payments WHERE restaurant_id = ? AND method = 'card']], { restaurantId }) or 0
    local tipToday = MySQL.scalar.await([[SELECT COALESCE(SUM(tip_amount),0) FROM ba_restaurant_payments WHERE restaurant_id = ? AND DATE(booked_at) = CURDATE()]], { restaurantId }) or 0
    local tipTotal = MySQL.scalar.await([[SELECT COALESCE(SUM(tip_amount),0) FROM ba_restaurant_payments WHERE restaurant_id = ?]], { restaurantId }) or 0
    local paymentRows = MySQL.query.await([[SELECT p.id, p.order_id, p.order_number, p.method, p.amount, p.tip_amount, p.cashier_name,
        DATE_FORMAT(p.booked_at, '%d.%m.%Y %H:%i') AS booked_time,
        o.items_json, o.subtotal, o.status AS order_status, o.payment_status
        FROM ba_restaurant_payments p
        LEFT JOIN ba_restaurant_orders o ON o.id = p.order_id AND o.restaurant_id = p.restaurant_id
        WHERE p.restaurant_id = ?
        ORDER BY p.booked_at DESC LIMIT ?]], { restaurantId, Config.CashStatsLimit or 50 }) or {}
    local cashiers = MySQL.query.await([[SELECT cashier_identifier, COALESCE(NULLIF(cashier_name,''), cashier_identifier, 'Unbekannt') AS cashier_name, COUNT(*) AS order_count, COALESCE(SUM(total),0) AS total, MIN(COALESCE(paid_at, updated_at)) AS first_paid_at, MAX(COALESCE(paid_at, updated_at)) AS last_paid_at, DATE_FORMAT(MIN(COALESCE(paid_at, updated_at)), '%d.%m.%Y %H:%i') AS first_paid_time, DATE_FORMAT(MAX(COALESCE(paid_at, updated_at)), '%d.%m.%Y %H:%i') AS last_paid_time FROM ba_restaurant_orders WHERE restaurant_id = ? AND payment_method = 'cash' AND payment_status = 'paid_cash' AND cash_closed_at IS NULL GROUP BY cashier_identifier, cashier_name ORDER BY last_paid_at DESC]], { restaurantId }) or {}
    local cashOrders = MySQL.query.await([[SELECT id, order_number, subtotal, tip_amount, total, cashier_identifier, COALESCE(NULLIF(cashier_name,''), cashier_identifier, '-') AS cashier_name, paid_at, updated_at, DATE_FORMAT(COALESCE(paid_at, updated_at), '%d.%m.%Y %H:%i') AS paid_time, items_json, cash_closed_at FROM ba_restaurant_orders WHERE restaurant_id = ? AND payment_method = 'cash' AND payment_status = 'paid_cash' ORDER BY COALESCE(paid_at, updated_at) DESC LIMIT ?]], { restaurantId, Config.CashStatsLimit or 50 })
    cb({ ok = true, categories = categories or {}, products = products or {}, menus = menus or {}, cashStats = { today = cashTotalToday, open = cashTotalOpen, total = cashTotalAll, cardToday = cardToday, cardTotal = cardTotal, tipToday = tipToday, tipTotal = tipTotal, cashiers = cashiers, orders = cashOrders or {}, payments = paymentRows }, currency = Config.Currency, restaurant = restaurant.label, theme = restaurant.theme })
end)

RegisterNetEvent('ba_restaurant:createOrder', function(data)
    local src = source
    if type(data) ~= 'table' or not data.restaurantId or type(data.items) ~= 'table' then TriggerClientEvent('ba_restaurant:orderFailed', src); return end
    local restaurantId = slug(data.restaurantId)
    local restaurant = getRestaurant(restaurantId)
    if not restaurant then return end
    local subtotal, sanitizedItems = 0.0, {}
    for _, item in ipairs(data.items) do
        local amount = tonumber(item.amount) or 0
        if amount > 0 and amount <= 50 then
            if item.type == 'menu' then
                local menu = MySQL.single.await('SELECT id, label, price, products_json FROM ba_restaurant_menus WHERE id = ? AND restaurant_id = ? AND enabled = 1', { item.id, restaurantId })
                if menu then
                    subtotal = subtotal + (tonumber(menu.price) * amount)
                    sanitizedItems[#sanitizedItems + 1] = { menu_id = menu.id, label = menu.label, price = tonumber(menu.price), amount = amount, products = menu.products_json }
                end
            else
                local product = MySQL.single.await('SELECT id, label, price, item_name FROM ba_restaurant_products WHERE id = ? AND restaurant_id = ? AND enabled = 1', { item.id, restaurantId })
                if product then
                    subtotal = subtotal + (tonumber(product.price) * amount)
                    sanitizedItems[#sanitizedItems + 1] = { product_id = product.id, label = product.label, price = tonumber(product.price), amount = amount, item_name = product.item_name }
                end
            end
        end
    end
    if #sanitizedItems == 0 then notify(src, 'Dein Warenkorb ist leer.', 'error'); TriggerClientEvent('ba_restaurant:orderFailed', src); return end
    local tipAmount = 0.0
    if Config.Tips == nil or Config.Tips.enabled ~= false then
        tipAmount = tonumber(data.tipAmount or data.tip_amount or data.tip) or 0.0
        if tipAmount < 0 then tipAmount = 0.0 end
        local maxTip = tonumber((Config.Tips or {}).maxAmount) or 1000.0
        if tipAmount > maxTip then tipAmount = maxTip end
    end
    tipAmount = math.floor((tipAmount + 0.005) * 100) / 100
    local total = math.floor((subtotal + tipAmount + 0.005) * 100) / 100
    local requestedPayment = tostring(data.paymentMethod or data.payment_method or data.method or data.payment or data.payType or data.paymentType or Config.DefaultPaymentMethod or 'card'):lower()
    local paymentMethod = requestedPayment == 'cash' and 'cash' or 'card'
    local paymentStatus = paymentMethod == 'card' and 'paid_card' or 'pending_cash'
    local xPlayer = nil
    local societyAccount = nil
    local societyAccountName = nil
    refreshFramework()
    if paymentMethod == 'card' and ESX then
        xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer or xPlayer.getAccount('bank').money < total then notify(src, 'Nicht genug Geld auf der Karte.', 'error'); TriggerClientEvent('ba_restaurant:orderFailed', src); return end
        societyAccountName = getSocietyAccountName(restaurant)
        societyAccount = getSharedSocietyAccount(societyAccountName)
        if not societyAccount or not societyAccount.addMoney then
            notify(src, 'Kartenzahlung nicht möglich: Fraktionskonto nicht gefunden.', 'error')
            local errorFields = {
                { name = 'Restaurant', value = restaurant.label or restaurantId },
                { name = 'Konto', value = tostring(societyAccountName) },
                { name = 'Summe', value = formatMoney(total) }
            }
            for _, field in ipairs(actorLogFields(src, 'Kunde')) do
                errorFields[#errorFields + 1] = field
            end
            supportLog('errors', 'Kartenzahlung abgebrochen', 'Das Fraktionskonto wurde nicht gefunden.', errorFields, 15158332)
            TriggerClientEvent('ba_restaurant:orderFailed', src)
            return
        end
    end
    local nextNumber = MySQL.scalar.await('SELECT COALESCE(MAX(order_number), 0) + 1 FROM ba_restaurant_orders WHERE restaurant_id = ?', { restaurantId }) or 1
    local orderId = MySQL.insert.await('INSERT INTO ba_restaurant_orders (restaurant_id, order_number, customer_identifier, status, payment_method, payment_status, subtotal, tip_amount, total, items_json, paid_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', {
        restaurantId, nextNumber, getIdentifier(src), paymentMethod == 'cash' and 'awaiting_payment' or 'open', paymentMethod, paymentStatus, subtotal, tipAmount, total, json.encode(sanitizedItems), paymentMethod == 'card' and os.date('%Y-%m-%d %H:%M:%S') or nil
    })
    if paymentMethod == 'cash' then
        giveOrderNote(src, nextNumber, restaurant.label, total, sanitizedItems, orderId, tipAmount, subtotal)
    else
        if xPlayer and xPlayer.removeAccountMoney then
            xPlayer.removeAccountMoney('bank', total)
        end
        if societyAccount then
            societyAccount.addMoney(total)
            logPayment(restaurantId, orderId, nextNumber, 'card', total, societyAccountName, getIdentifier(src), getCharacterName(src), tipAmount)
        end
        givePaidReceipt(src, nextNumber, restaurant.label, total, sanitizedItems, 'Mit Karte bezahlt', 'card', orderId, tipAmount, subtotal)
    end
    local orderLogFields = {
        { name = 'Restaurant', value = restaurant.label or restaurantId },
        { name = 'Bestellung', value = '#' .. tostring(nextNumber) },
        { name = 'Zahlung', value = paymentMethod == 'cash' and 'Bar' or 'Karte' },
        { name = 'Artikel', value = tostring(#sanitizedItems) },
        { name = 'Inhalt', value = formatOrderLines(sanitizedItems), inline = false },
        { name = 'Trinkgeld', value = formatMoney(tipAmount) },
        { name = 'Summe', value = formatMoney(total) },
        { name = 'Beleg', value = paymentMethod == 'cash' and 'Bestellzettel ausgegeben' or 'Kassenbon ausgegeben' }
    }
    if paymentMethod == 'card' then
        orderLogFields[#orderLogFields + 1] = { name = 'Konto', value = tostring(societyAccountName) }
    end
    for _, field in ipairs(actorLogFields(src, paymentMethod == 'cash' and 'Bestellt von' or 'Bezahlt von')) do
        orderLogFields[#orderLogFields + 1] = field
    end
    supportLog('orders', 'Neue Bestellung', paymentMethod == 'cash' and 'Eine Bar-Bestellung wartet auf Zahlung.' or 'Eine bezahlte Karten-Bestellung wurde erstellt und verbucht.', orderLogFields, paymentMethod == 'cash' and 16763904 or 5763719)
    TriggerClientEvent('ba_restaurant:orderCreated', src, { orderId = orderId, orderNumber = nextNumber, restaurant = restaurant.label, paymentMethod = paymentMethod, paymentStatus = paymentStatus, paid = paymentMethod == 'card', subtotal = subtotal, tipAmount = tipAmount, tip_amount = tipAmount, total = total, items = sanitizedItems })
    TriggerClientEvent('ba_restaurant:kitchenRefresh', -1, restaurantId)
    TriggerClientEvent('ba_restaurant:pickupRefresh', -1, restaurantId)
    if paymentMethod == 'card' then
        TriggerClientEvent('ba_restaurant:monitorOrderSound', -1, restaurantId, 'kitchen', orderId)
    end
end)

callback('ba_restaurant:getMonitorOrders', function(_, cb, restaurantId)
    restaurantId = slug(restaurantId)
    if not getRestaurant(restaurantId) then cb({ kitchen = {}, pickup = {} }) return end
    local rows = MySQL.query.await([[SELECT id, order_number, status, payment_status, total, items_json, created_at
        FROM ba_restaurant_orders
        WHERE restaurant_id = ? AND status IN ('open','in_progress','ready')
        ORDER BY created_at ASC LIMIT 30]], { restaurantId }) or {}
    local kitchen, pickup = {}, {}
    for _, order in ipairs(rows) do
        if order.status == 'open' or order.status == 'in_progress' then kitchen[#kitchen + 1] = order end
        if order.status == 'open' or order.status == 'in_progress' or order.status == 'ready' then pickup[#pickup + 1] = order end
    end
    cb({ kitchen = kitchen, pickup = pickup })
end)

callback('ba_restaurant:getOrders' , function(source, cb, restaurantId, view)
    restaurantId = slug(restaurantId)
    if not getRestaurant(restaurantId) then cb({}) return end
    if (view == 'kitchen' or view == 'cashier') and not canOpenPoint(source, restaurantId, view) then
        cb({ ok = false, error = 'Keine Berechtigung.' })
        return
    end
    local statuses = "'open','in_progress'"
    if view == 'kitchen' then statuses = "'open','in_progress','ready'" end
    if view == 'pickup' then statuses = "'open','in_progress','ready'" end
    if view == 'cashier' then statuses = "'awaiting_payment'" end
    local orders = MySQL.query.await(('SELECT * FROM ba_restaurant_orders WHERE restaurant_id = ? AND status IN (%s) ORDER BY created_at ASC'):format(statuses), { restaurantId })
    cb(orders or {})
end)

RegisterNetEvent('ba_restaurant:updateOrderStatus', function(restaurantId, orderId, status)
    local src = source
    restaurantId = slug(restaurantId)
    if not hasRestaurantJob(src, restaurantId) then return end
    local allowed = { open = true, in_progress = true, ready = true, completed = true, awaiting_payment = true }
    if not allowed[status] then return end
    local affected = MySQL.update.await('UPDATE ba_restaurant_orders SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND restaurant_id = ?', { status, orderId, restaurantId }) or 0
    if affected > 0 then
        local order = MySQL.single.await('SELECT order_number, total, tip_amount FROM ba_restaurant_orders WHERE id = ? AND restaurant_id = ?', { orderId, restaurantId })
        local restaurant = getRestaurant(restaurantId)
        local statusLabels = {
            open = 'In Bearbeitung',
            in_progress = 'In Bearbeitung',
            ready = 'Abholbereit',
            completed = 'Abgeschlossen',
            awaiting_payment = 'Wartet auf Zahlung'
        }
        local statusFields = {
            { name = 'Restaurant', value = restaurant and restaurant.label or restaurantId },
            { name = 'Bestellung', value = '#' .. tostring(order and order.order_number or orderId) },
            { name = 'Status', value = statusLabels[status] or status },
            { name = 'Summe', value = formatMoney(order and order.total or 0) }
        }
        for _, field in ipairs(actorLogFields(src, 'Mitarbeiter')) do
            statusFields[#statusFields + 1] = field
        end
        supportLog('status', 'Bestellstatus geaendert', 'Eine Bestellung hat einen neuen Status erhalten.', statusFields, status == 'completed' and 5763719 or 3447003)
    end
    TriggerClientEvent('ba_restaurant:kitchenRefresh', -1, restaurantId)
    TriggerClientEvent('ba_restaurant:pickupRefresh', -1, restaurantId)
    if status == 'ready' then
        TriggerClientEvent('ba_restaurant:monitorOrderSound', -1, restaurantId, 'pickup', orderId)
    end
end)


RegisterNetEvent('ba_restaurant:cashierPayment', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local restaurantId = slug(data.restaurantId)
    if not canOpenPoint(src, restaurantId, 'cashier') then notify(src, 'Keine Berechtigung für die Kasse.', 'error') return end
    local orderId = tonumber(data.orderId)
    local order = MySQL.single.await('SELECT * FROM ba_restaurant_orders WHERE id = ? AND restaurant_id = ? AND status = ? AND payment_method = ?', { orderId, restaurantId, 'awaiting_payment', 'cash' })
    local affected = 0
    if order then
        affected = MySQL.update.await('UPDATE ba_restaurant_orders SET status = ?, payment_method = ?, payment_status = ?, cashier_identifier = ?, cashier_name = ?, paid_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND restaurant_id = ? AND status = ? AND payment_method = ?', { 'open', 'cash', 'paid_cash', getIdentifier(src), getCharacterName(src), orderId, restaurantId, 'awaiting_payment', 'cash' }) or 0
    end
    if affected and affected > 0 then
        local restaurant = getRestaurant(restaurantId)
        local items = {}
        pcall(function() items = json.decode(order.items_json or '[]') or {} end)
        logPayment(restaurantId, order.id, order.order_number, 'cash', order.total, nil, getIdentifier(src), getCharacterName(src), order.tip_amount)
        local paymentFields = {
            { name = 'Restaurant', value = restaurant and restaurant.label or restaurantId },
            { name = 'Bestellung', value = '#' .. tostring(order.order_number) },
            { name = 'Inhalt', value = formatOrderLines(items), inline = false },
            { name = 'Trinkgeld', value = formatMoney(order.tip_amount) },
            { name = 'Summe', value = formatMoney(order.total) },
            { name = 'Beleg', value = 'Kassenbon ausgegeben' }
        }
        for _, field in ipairs(actorLogFields(src, 'Kassierer')) do
            paymentFields[#paymentFields + 1] = field
        end
        supportLog('payments', 'Barzahlung verbucht', 'Eine Barzahlung wurde angenommen und die Bestellung an die Kueche freigegeben.', paymentFields, 16763904)
        givePaidReceipt(src, order.order_number, restaurant and restaurant.label or restaurantId, order.total, items, 'Bar bezahlt', 'cash', order.id, order.tip_amount, order.subtotal)
        notify(src, 'Barzahlung vermerkt. Kassenbon wurde erstellt und die Bestellung an die Küche freigegeben.', 'success')
        TriggerClientEvent('ba_restaurant:kitchenRefresh', -1, restaurantId)
        TriggerClientEvent('ba_restaurant:pickupRefresh', -1, restaurantId)
        TriggerClientEvent('ba_restaurant:cashierRefresh', -1, restaurantId)
        TriggerClientEvent('ba_restaurant:managerRefresh', -1, restaurantId)
        TriggerClientEvent('ba_restaurant:monitorOrderSound', -1, restaurantId, 'kitchen', order.id)
    else
        notify(src, 'Bestellung nicht gefunden oder bereits bearbeitet.', 'error')
    end
end)

RegisterNetEvent('ba_restaurant:closeCashierShift', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local restaurantId = slug(data.restaurantId)
    if not hasManagementAccess(src, restaurantId) then notify(src, 'Keine Berechtigung.', 'error') return end
    local cashierIdentifier = sanitizeText(data.cashierIdentifier, 128)
    if cashierIdentifier == '' then notify(src, 'Kassierer fehlt.', 'error') return end
    local affected = MySQL.update.await([[UPDATE ba_restaurant_orders
        SET cash_closed_at = CURRENT_TIMESTAMP, cash_closed_by = ?, cash_closed_by_name = ?, updated_at = CURRENT_TIMESTAMP
        WHERE restaurant_id = ? AND payment_method = 'cash' AND payment_status = 'paid_cash' AND cash_closed_at IS NULL AND cashier_identifier = ?]], {
        getIdentifier(src), getCharacterName(src), restaurantId, cashierIdentifier
    }) or 0
    if affected > 0 then
        local restaurant = getRestaurant(restaurantId)
        local cashierFields = {
            { name = 'Restaurant', value = restaurant and restaurant.label or restaurantId },
            { name = 'Kassierer', value = sanitizeText(data.cashierName or cashierIdentifier, 128) },
            { name = 'Barzahlungen', value = tostring(affected) }
        }
        for _, field in ipairs(actorLogFields(src, 'Manager')) do
            cashierFields[#cashierFields + 1] = field
        end
        supportLog('cashier', 'Kassensturz abgeschlossen', 'Ein Manager hat offene Barzahlungen abgeschlossen.', cashierFields, 5763719)
    end
    notify(src, affected > 0 and ('Kassensturz abgeschlossen: ' .. affected .. ' Barzahlung(en).') or 'Keine offenen Barzahlungen gefunden.', affected > 0 and 'success' or 'info')
    TriggerClientEvent('ba_restaurant:managerRefresh', src, restaurantId)
end)

RegisterNetEvent('ba_restaurant:saveProduct', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local restaurantId = slug(data.restaurantId)
    if not hasManagementAccess(src, restaurantId) then notify(src, 'Keine Berechtigung.', 'error') return end
    local category, label = sanitizeText(data.category, 64), sanitizeText(data.label, 128)
    local description, image = sanitizeText(data.description, 2000), sanitizeText(data.image, 512)
    local itemName = sanitizeText(data.item_name, 128)
    local price = tonumber(data.price) or 0
    if category == '' or label == '' then notify(src, 'Produkt braucht Kategorie und Namen.', 'error') return end
    if price < 0 then price = 0 end
    image = image:gsub('%.%.', '')
    local categoryExists = MySQL.scalar.await('SELECT COUNT(*) FROM ba_restaurant_categories WHERE restaurant_id = ? AND name = ?', { restaurantId, category })
    if not categoryExists or categoryExists < 1 then notify(src, 'Kategorie existiert nicht.', 'error') return end
    if data.id then
        MySQL.update.await('UPDATE ba_restaurant_products SET category = ?, label = ?, description = ?, price = ?, item_name = ?, image = ?, enabled = ? WHERE id = ? AND restaurant_id = ?', { category, label, description, price, itemName, image, data.enabled and 1 or 0, data.id, restaurantId })
    else
        MySQL.insert.await('INSERT INTO ba_restaurant_products (restaurant_id, category, label, description, price, item_name, image, enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', { restaurantId, category, label, description, price, itemName, image, data.enabled and 1 or 0 })
    end
    notify(src, 'Produkt gespeichert.', 'success')
    TriggerClientEvent('ba_restaurant:managerRefresh', src, restaurantId)
    TriggerClientEvent('ba_restaurant:menuRefresh', -1, restaurantId)
end)

local function refreshManager(src, restaurantId) TriggerClientEvent('ba_restaurant:managerRefresh', src, restaurantId) end

local function isDisabled(value)
    return value == false or tonumber(value) == 0 or tostring(value) == '0'
end

RegisterNetEvent('ba_restaurant:saveCategory', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local restaurantId = slug(data.restaurantId)
    if not hasManagementAccess(src, restaurantId) then notify(src, 'Keine Berechtigung.', 'error') return end

    local label = sanitizeText(data.label or data.name, 128)
    local name = slug(label)
    local image = sanitizeText(data.image, 512):gsub('%.%.', '')

    if name == '' or label == '' then notify(src, 'Kategorie braucht einen Namen.', 'error') return end

    if data.id then
        local oldName = MySQL.scalar.await('SELECT name FROM ba_restaurant_categories WHERE id = ? AND restaurant_id = ?', { data.id, restaurantId })
        MySQL.update.await('UPDATE ba_restaurant_categories SET name = ?, label = ?, image = ?, icon = NULL, sort_order = ?, enabled = ? WHERE id = ? AND restaurant_id = ?', { name, label, image, tonumber(data.sort_order) or 1, data.enabled and 1 or 0, data.id, restaurantId })
        if oldName and oldName ~= name then
            MySQL.update.await('UPDATE ba_restaurant_products SET category = ? WHERE restaurant_id = ? AND category = ?', { name, restaurantId, oldName })
        end
    else
        MySQL.insert.await('INSERT INTO ba_restaurant_categories (restaurant_id, name, label, image, sort_order, enabled) VALUES (?, ?, ?, ?, ?, ?)', { restaurantId, name, label, image, tonumber(data.sort_order) or 1, data.enabled and 1 or 0 })
    end

    notify(src, 'Kategorie gespeichert.', 'success')
    refreshManager(src, restaurantId)
    TriggerClientEvent('ba_restaurant:menuRefresh', -1, restaurantId)
end)

RegisterNetEvent('ba_restaurant:deleteCategory', function(restaurantId, id)
    local src = source
    restaurantId = slug(restaurantId)
    if not hasManagementAccess(src, restaurantId) then notify(src, 'Keine Berechtigung.', 'error') return end
    MySQL.update.await('UPDATE ba_restaurant_categories SET enabled = 0 WHERE id = ? AND restaurant_id = ?', { id, restaurantId })
    notify(src, 'Kategorie deaktiviert.', 'success')
    refreshManager(src, restaurantId)
    TriggerClientEvent('ba_restaurant:menuRefresh', -1, restaurantId)
end)

RegisterNetEvent('ba_restaurant:hardDeleteCategory', function(restaurantId, id)
    local src = source
    restaurantId = slug(restaurantId)
    id = tonumber(id)
    if not id then return end
    if not hasManagementAccess(src, restaurantId) then notify(src, 'Keine Berechtigung.', 'error') return end

    local category = MySQL.single.await('SELECT id, enabled FROM ba_restaurant_categories WHERE id = ? AND restaurant_id = ?', { id, restaurantId })
    if not category then notify(src, 'Kategorie nicht gefunden.', 'error') return end
    if not isDisabled(category.enabled) then notify(src, 'Kategorie erst deaktivieren, dann loeschen.', 'error') return end

    MySQL.update.await('DELETE FROM ba_restaurant_categories WHERE id = ? AND restaurant_id = ? AND enabled = 0', { id, restaurantId })
    notify(src, 'Kategorie endgueltig geloescht.', 'success')
    refreshManager(src, restaurantId)
    TriggerClientEvent('ba_restaurant:menuRefresh', -1, restaurantId)
end)

RegisterNetEvent('ba_restaurant:deleteProduct', function(restaurantId, id)
    local src = source
    restaurantId = slug(restaurantId)
    if not hasManagementAccess(src, restaurantId) then notify(src, 'Keine Berechtigung.', 'error') return end
    MySQL.update.await('UPDATE ba_restaurant_products SET enabled = 0 WHERE id = ? AND restaurant_id = ?', { id, restaurantId })
    notify(src, 'Produkt deaktiviert.', 'success')
    refreshManager(src, restaurantId)
    TriggerClientEvent('ba_restaurant:menuRefresh', -1, restaurantId)
end)

RegisterNetEvent('ba_restaurant:hardDeleteProduct', function(restaurantId, id)
    local src = source
    restaurantId = slug(restaurantId)
    id = tonumber(id)
    if not id then return end
    if not hasManagementAccess(src, restaurantId) then notify(src, 'Keine Berechtigung.', 'error') return end

    local product = MySQL.single.await('SELECT id, enabled FROM ba_restaurant_products WHERE id = ? AND restaurant_id = ?', { id, restaurantId })
    if not product then notify(src, 'Produkt nicht gefunden.', 'error') return end
    if not isDisabled(product.enabled) then notify(src, 'Produkt erst deaktivieren, dann loeschen.', 'error') return end

    MySQL.update.await('DELETE FROM ba_restaurant_products WHERE id = ? AND restaurant_id = ? AND enabled = 0', { id, restaurantId })
    notify(src, 'Produkt endgueltig geloescht.', 'success')
    refreshManager(src, restaurantId)
    TriggerClientEvent('ba_restaurant:menuRefresh', -1, restaurantId)
end)

RegisterNetEvent('ba_restaurant:saveMenu', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local restaurantId = slug(data.restaurantId)
    if not hasManagementAccess(src, restaurantId) then notify(src, 'Keine Berechtigung.', 'error') return end
    local label = sanitizeText(data.label, 128)
    if label == '' then notify(src, 'Menü braucht einen Namen.', 'error') return end
    local products = type(data.products) == 'table' and data.products or {}
    local price = tonumber(data.price) or 0
    if price <= 0 and #products > 0 then
        local sum = 0
        for _, productId in ipairs(products) do
            local p = MySQL.single.await('SELECT price FROM ba_restaurant_products WHERE id = ? AND restaurant_id = ?', { productId, restaurantId })
            if p then sum = sum + tonumber(p.price or 0) end
        end
        price = sum
    end
    if data.id then
        MySQL.update.await('UPDATE ba_restaurant_menus SET label = ?, description = ?, price = ?, products_json = ?, enabled = 1 WHERE id = ? AND restaurant_id = ?', { label, sanitizeText(data.description, 2000), price, json.encode(products), data.id, restaurantId })
    else
        MySQL.insert.await('INSERT INTO ba_restaurant_menus (restaurant_id, label, description, price, products_json, enabled) VALUES (?, ?, ?, ?, ?, 1)', { restaurantId, label, sanitizeText(data.description, 2000), price, json.encode(products) })
    end
    notify(src, 'Menü gespeichert.', 'success')
    refreshManager(src, restaurantId)
    TriggerClientEvent('ba_restaurant:menuRefresh', -1, restaurantId)
end)

RegisterNetEvent('ba_restaurant:deleteMenu', function(restaurantId, id)
    local src = source
    restaurantId = slug(restaurantId)
    if not hasManagementAccess(src, restaurantId) then notify(src, 'Keine Berechtigung.', 'error') return end
    MySQL.update.await('UPDATE ba_restaurant_menus SET enabled = 0 WHERE id = ? AND restaurant_id = ?', { id, restaurantId })
    notify(src, 'Menü deaktiviert.', 'success')
    refreshManager(src, restaurantId)
    TriggerClientEvent('ba_restaurant:menuRefresh', -1, restaurantId)
end)
