fx_version 'cerulean'
game 'gta5'

name 'ba_restaurant_receipts'
author 'Baliux Codeworks'
description 'Item Kassenzettel'
version '1.0.0'

lua54 'yes'

ui_page 'html/index.html'

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

files {
    'html/index.html',
    'html/css/style.css',
    'html/js/app.js'
}
