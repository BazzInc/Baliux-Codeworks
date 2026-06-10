Config = {}

Config.Debug = true
Config.Locale = 'de'

Config.InteractKey = 38 -- E
Config.DrawDistance = 20.0
Config.InteractDistance = 2.0
Config.Currency = '$'

Config.Target = {
    enabled = true,
    resource = 'ox_target',
    debug = false
}

Config.AdminCreator = {
    command = 'restaurantcreator',
    ace = 'ba_restaurant.creator',
    allowConsole = true
}

Config.Management = {
    requireBoss = true,
    allowedGrades = {
        boss = true,
        owner = true
    }
    -- minGrade = 3
}

Config.OrderNumberPrefix = ''
Config.DefaultPaymentMethod = 'card'

Config.OrderNoteItem = 'restaurant_order_note'
Config.ReceiptItem = 'restaurant_receipt'
Config.OrderPaperItem = Config.OrderNoteItem 
Config.GiveOrderPaperItem = true
Config.CashReceiptItem = Config.ReceiptItem
Config.GiveCashReceiptItem = Config.GiveOrderPaperItem

Config.CashStatsLimit = 50

Config.Tips = {
    enabled = true,
    presets = { 10, 20, 30 },
    maxAmount = 1000.0
}

Config.MonitorSounds = {
    kitchen = {
        enabled = true,
        soundName = 'CHECKPOINT_NORMAL',
        soundSet = 'HUD_MINI_GAME_SOUNDSET'
    },
    pickup = {
        enabled = true,
        soundName = 'TIMER_STOP',
        soundSet = 'HUD_MINI_GAME_SOUNDSET'
    }
}

Config.Restaurants = {}

Config.Notifications = {
    useESX = true
}


Config.MonitorProps = {
    kitchen = 'prop_tv_flat_01',
    pickup = 'prop_tv_flat_01'
}

Config.MonitorModels = {
    large = {
        kitchen = 'prop_tv_flat_01',
        pickup = 'prop_tv_flat_01'
    },
    small = {
        kitchen = 'prop_tv_flat_02',
        pickup = 'prop_tv_flat_02'
    }
}

Config.MonitorPlacement = {
    moveStep = 0.03,
    rotateStep = 2.5,
    maxDistance = 8.0
}

Config.MonitorLiveDisplay = {
    enabled = true,
    drawDistance = 18.0,
    refreshMs = 1500,
    maxRows = 8,
    useDuiScreen = true,
    disableMonitorInteraction = true,
    interaction = {
        kitchen = true,
        pickup = false 
    },
    duiWidth = 1920,
    duiHeight = 1080,
    screenWidth = 2.05,
    screenHeight = 1.15,
    screenOffsetForward = 0.07,
    screenOffsetUp = 0.74,
    fallbackText = false,
    drawBothSides = true
}

Config.MonitorSizes = {
    large = {
        label = 'Gross',
        screenWidth = 2.05,
        screenHeight = 1.15,
        screenOffsetUp = 0.74,
        screenOffsetForward = 0.07
    },
    small = {
        label = 'Klein',
        screenWidth = 1.18,
        screenHeight = 0.64,
        screenOffsetUp = 0.43,
        screenOffsetForward = -0.055,
        drawBothSides = false
    }
}
