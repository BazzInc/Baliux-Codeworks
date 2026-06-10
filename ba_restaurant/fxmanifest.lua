fx_version 'cerulean'
game 'gta5'

name 'ba_restaurant'
author 'Baliux Codeworks'
description 'Restaurant Creator'
version '1.1.1'

lua54 'yes'

ui_page 'html/index.html'

shared_scripts {
    '@oxmysql/lib/MySQL.lua',
    'config.lua',
    'shared/framework.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js',
    'html/sounds/*.wav'
}

dependency 'ba_core'
dependency 'oxmysql'
dependency 'ox_target'
