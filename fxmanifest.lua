fx_version 'cerulean'
game 'gta5'

author 'Xinao'
description 'Sistema de Mesa de Drogas'
version '1.0.0'

dependency 'vrp'

shared_scripts {
  'config.lua'
}

client_scripts {
  '@vrp/lib/utils.lua',
  'client.lua'
}

server_scripts {
  '@vrp/lib/utils.lua',
  'server.lua'
}

-- Lista de eventos seguros para rede
server_events {
    'mesa_droga:objeto_criado',
    'mesa_droga:criacao_falhou',
    'mesa_droga:sincronizar_mesa',
    'mesa_droga:validar_mesa',
    'mesa_droga:atualizar_estado',
    'mesa_droga:remover_mesa',
    'mesa_droga:mesa_validada',
    'mesa_droga:remover_mesa_registrada',
    'mesa_droga:sync_mesa',
    'mesa_droga:update_position',
    'mesa_droga:solicitar_novo_npc',
    'mesa_droga:spawn_npc_para_todos',
    'mesa_droga:remover_npc_para_todos'
}

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/script.js',
  'html/img/weedsack.png',
  'html/img/methsack.png',
  'html/img/cocaine.png'
}
