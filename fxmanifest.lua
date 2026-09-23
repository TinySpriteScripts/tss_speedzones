fx_version 'cerulean'
game 'gta5'

author 'TinySprite'
description 'One-time average-speed freeroam challenges for StreetKings Framework'
version '1.0.0'

dependencies {
    'ox_lib',
    'streetkings'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_script 'client.lua'
server_script 'server.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js'
}

