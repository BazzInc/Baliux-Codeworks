fx_version 'cerulean'
game 'gta5'

name 'ba_core'
author 'Baliux Codeworks'
description 'Baliux Core'
version '1.0.0'
lua54 'yes'

shared_scripts {
    'shared/config.lua',
    'shared/framework.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

exports {
    'GetFramework',
    'GetFrameworkName',
    'IsFrameworkReady'
}

server_exports {
    'GetFramework',
    'GetFrameworkName',
    'IsFrameworkReady'
}
