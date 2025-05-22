local Tunnel = module("vrp","lib/Tunnel")
local Proxy = module("vrp","lib/Proxy")
vRP = Proxy.getInterface("vRP")

local vRPserver = Tunnel.getInterface("vRP")
local mesaDroga = {}
Tunnel.bindInterface("mesa_droga",mesaDroga)
Proxy.addInterface("mesa_droga",mesaDroga)

-- Lista de todos os eventos que precisam ser registrados
local eventosParaRegistrar = {
    "mesa_droga:usar",
    "mesa_droga:guardar_mesa",
    "mesa_droga:abrir_painel",
    "mesa_droga:abrir_nui_com_drogas",
    "mesa_droga:atualizar_droga",
    "mesa_droga:solicitar_novo_npc",
    "mesa_droga:spawn_npc_para_todos",
    "mesa_droga:remover_npc_para_todos",
    "mesa_droga:sync_mesa",
    "mesa_droga:registro_confirmado",
    "mesa_droga:remover_mesa",
    "mesa_droga:recriar_mesa",
    "mesa_droga:sync_creation_response",
    "mesa_droga:objeto_criado",
    "mesa_droga:criacao_falhou",
    "mesa_droga:sincronizar_mesa",
    "mesa_droga:validar_mesa",
    "mesa_droga:atualizar_estado",
    "mesa_droga:mesa_validada",
    "mesa_droga:remover_mesa_registrada",
    "mesa_droga:update_position",
    "objects:Table",
    "objects:Adicionar"
}

-- Registra todos os eventos
for _, evento in ipairs(eventosParaRegistrar) do
    RegisterNetEvent(evento)
end

-- Variáveis locais
local emVenda = false
local mesaInventario = {}
local mesaAtiva = false
local mesaCoords = nil
local mesaEntidade = nil
local clienteNPC = nil
local aguardandoCliente = false
local vendaCooldown = 0
local npcsSpawnados = {}
local mesaAtualId = nil
local ultimoSpawnTime = 0
local ultimaVenda = 0
local npcAtivo = false
local tentativasRecriacao = 0
local mesaHash = nil
local mesaHeading = 0.0
local mesaNetId = nil
local tentativasValidacao = 0
local maxTentativasValidacao = 3
local tempoEntreValidacoes = 1000 -- 1 segundo
local ultimaValidacao = 0

-- Estados da mesa
local MESA_STATES = {
    NONE = "none",
    CREATING = "creating",
    ACTIVE = "active",
    REMOVING = "removing"
}

local mesaState = MESA_STATES.NONE

-- Carregar modelo da mesa
Citizen.CreateThread(function()
    mesaHash = GetHashKey(Config.MesaModel)
    RequestModel(mesaHash)
    while not HasModelLoaded(mesaHash) do 
        Wait(10) 
    end
end)

-- Função para desenhar texto na tela
function DwText(Text, Font, x, y, Scale, r, g, b, a)
    SetTextFont(Font)
    SetTextScale(Scale, Scale)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(Text)
    DrawText(x, y)
end

-- Função para desenhar linhas de referência
function DrawGraphOutline(Object)
    local Coords = GetEntityCoords(Object)
    local x, y, z = Coords - GetOffsetFromEntityInWorldCoords(Object, 2.0, 0.0, 0.0),
        Coords - GetOffsetFromEntityInWorldCoords(Object, 0.0, 2.0, 0.0),
        Coords - GetOffsetFromEntityInWorldCoords(Object, 0.0, 0.0, 2.0)
    local x1, x2, y1, y2, z1, z2 = Coords - x, Coords + x, Coords - y, Coords + y, Coords - z, Coords + z
    DrawLine(x1.x, x1.y, x1.z, x2.x, x2.y, x2.z, 255, 0, 0, 255)
    DrawLine(y1.x, y1.y, y1.z, y2.x, y2.y, y2.z, 0, 0, 255, 255)
    DrawLine(z1.x, z1.y, z1.z, z2.x, z2.y, z2.z, 0, 255, 0, 255)
end

-- Helper: carregar animação
local function loadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Citizen.Wait(10)
        end
    end
end

-- Helper: carregar modelo
local function loadModel(model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    local startTime = GetGameTimer()
    while not HasModelLoaded(hash) do
        Citizen.Wait(10)
        if GetGameTimer() - startTime > 5000 then -- timeout após 5 segundos
            return false
        end
    end
    return true
end

-- Função de controle de objeto
function mesaDroga.ObjectControlling(Model)
    local GroundZ = 0.0
    local Aplication = false
    local ObjectCoords = nil
    local ObjectHeading = 0.0

    if loadModel(Model) then
        local Progress = true
        local Ped = PlayerPedId()
        local Heading = GetEntityHeading(Ped)
        local Coords = GetOffsetFromEntityInWorldCoords(Ped, 0.0, 1.0, 0.0)
        
        -- Cria objeto temporário para posicionamento
        local NextObject = CreateObject(Model, Coords.x, Coords.y, Coords.z, false, false, false)
        SetEntityHeading(NextObject, Heading)
        SetEntityAlpha(NextObject, 175, false)
        PlaceObjectOnGroundProperly(NextObject)
        SetEntityCollision(NextObject, false, false)
        FreezeEntityPosition(NextObject, true)

        while Progress do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            
            -- Verifica distância do jogador
            if #(playerCoords - GetEntityCoords(NextObject)) > 10.0 then
                DeleteEntity(NextObject)
                return false, nil, nil
            end
            
            DrawGraphOutline(NextObject)

            DwText("~g~F~w~  CANCELAR", 4, 0.015, 0.62, 0.38, 255, 255, 255, 255)
            DwText("~g~E~w~  COLOCAR OBJETO", 4, 0.015, 0.65, 0.38, 255, 255, 255, 255)
            DwText("~y~PAGE UP~w~  PARA CIMA", 4, 0.015, 0.68, 0.38, 255, 255, 255, 255)
            DwText("~y~PAGE DOWN~w~  PARA BAIXO", 4, 0.015, 0.71, 0.38, 255, 255, 255, 255)
            DwText("~y~SCROLL UP~w~  GIRA ESQUERDA", 4, 0.015, 0.74, 0.38, 255, 255, 255, 255)
            DwText("~y~SCROLL DOWN~w~  GIRA DIREITA", 4, 0.015, 0.77, 0.38, 255, 255, 255, 255)
            DwText("~y~ARROW UP~w~  PARA LONGE", 4, 0.015, 0.80, 0.38, 255, 255, 255, 255)
            DwText("~y~ARROW DOWN~w~  PARA PERTO", 4, 0.015, 0.83, 0.38, 255, 255, 255, 255)
            DwText("~y~ARROW LEFT~w~  PARA ESQUERDA", 4, 0.015, 0.86, 0.38, 255, 255, 255, 255)
            DwText("~y~ARROW RIGHT~w~  PARA DIREITA", 4, 0.015, 0.89, 0.38, 255, 255, 255, 255)

            if IsControlJustPressed(1, 38) then
                -- Obtém coordenadas finais
                ObjectCoords = GetEntityCoords(NextObject)
                ObjectHeading = GetEntityHeading(NextObject)
                
                -- Verifica se a posição é válida
                local success, groundZ = GetGroundZFor_3dCoord(ObjectCoords.x, ObjectCoords.y, ObjectCoords.z + 0.1, true)
                if success then
                    ObjectCoords = vector3(ObjectCoords.x, ObjectCoords.y, groundZ)
                    Aplication = true
                else
                    TriggerEvent("Notify", "vermelho", "Posição inválida.")
                end
                Progress = false
            end

            if IsControlJustPressed(0, 49) then
                Progress = false
            end

            if IsDisabledControlPressed(1, 10) then
                local pos = GetEntityCoords(NextObject)
                SetEntityCoords(NextObject, pos.x, pos.y, pos.z + 0.01, false, false, false)
            end

            if IsDisabledControlPressed(1, 11) then
                local pos = GetEntityCoords(NextObject)
                SetEntityCoords(NextObject, pos.x, pos.y, pos.z - 0.01, false, false, false)
            end

            if IsDisabledControlPressed(1, 172) then
                local pos = GetEntityCoords(NextObject)
                local forward = GetEntityForwardVector(playerPed)
                SetEntityCoords(NextObject, pos.x + forward.x * 0.01, pos.y + forward.y * 0.01, pos.z, false, false, false)
            end

            if IsDisabledControlPressed(1, 173) then
                local pos = GetEntityCoords(NextObject)
                local forward = GetEntityForwardVector(playerPed)
                SetEntityCoords(NextObject, pos.x - forward.x * 0.01, pos.y - forward.y * 0.01, pos.z, false, false, false)
            end

            if IsDisabledControlPressed(1, 174) then
                local pos = GetEntityCoords(NextObject)
                local right = GetEntityRightVector(playerPed)
                SetEntityCoords(NextObject, pos.x - right.x * 0.01, pos.y - right.y * 0.01, pos.z, false, false, false)
            end

            if IsDisabledControlPressed(1, 175) then
                local pos = GetEntityCoords(NextObject)
                local right = GetEntityRightVector(playerPed)
                SetEntityCoords(NextObject, pos.x + right.x * 0.01, pos.y + right.y * 0.01, pos.z, false, false, false)
            end

            if IsControlJustPressed(0, 180) then
                SetEntityHeading(NextObject, GetEntityHeading(NextObject) + 2.5)
            end

            if IsControlJustPressed(0, 181) then
                SetEntityHeading(NextObject, GetEntityHeading(NextObject) - 2.5)
            end

            Wait(1)
        end

        DeleteEntity(NextObject)
    end

    return Aplication, ObjectCoords, ObjectHeading
end

-- Função para limpar estado da mesa
local function limparEstadoMesa()
    print("[mesa_droga] Limpando estado da mesa")
    mesaEntidade = nil
    mesaInventario = {}
    mesaAtiva = false
    mesaCoords = nil
    mesaHeading = nil
    emVenda = false
    aguardandoCliente = false
    npcAtivo = false
    mesaAtualId = nil
end

-- Função para remover mesa
local function removerMesa()
    print("[mesa_droga] Iniciando processo de remoção da mesa")
    
    -- Remove a entidade da mesa
    if mesaEntidade then
        if DoesEntityExist(mesaEntidade) then
            print("[mesa_droga] Tentando remover entidade da mesa")
            
            -- Força controle da entidade
            if not NetworkHasControlOfEntity(mesaEntidade) then
                print("[mesa_droga] Solicitando controle da entidade")
                NetworkRequestControlOfEntity(mesaEntidade)
                Wait(100)
            end
            
            -- Tenta deletar a entidade
            local netId = NetworkGetNetworkIdFromEntity(mesaEntidade)
            if netId and netId ~= 0 then
                print("[mesa_droga] Configurando migração do netId:", netId)
                SetNetworkIdCanMigrate(netId, true)
            end
            
            -- Força remoção
            SetEntityAsMissionEntity(mesaEntidade, true, true)
            DeleteEntity(mesaEntidade)
            
            -- Verifica se foi realmente removida
            if DoesEntityExist(mesaEntidade) then
                print("[mesa_droga] Falha na primeira tentativa, tentando novamente")
                SetEntityCoords(mesaEntidade, 0.0, 0.0, 0.0)
                DeleteEntity(mesaEntidade)
            end
        end
        mesaEntidade = nil
    end
    
    -- Remove NPCs
    print("[mesa_droga] Removendo NPCs")
    for _, npc in pairs(npcsSpawnados) do
        if DoesEntityExist(npc) then
            DeleteEntity(npc)
        end
    end
    npcsSpawnados = {}
    
    if clienteNPC and DoesEntityExist(clienteNPC) then
        DeleteEntity(clienteNPC)
    end
    clienteNPC = nil
    
    -- Limpa UI
    print("[mesa_droga] Limpando UI")
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "hide" })
    
    -- Limpa estado
    limparEstadoMesa()
    
    print("[mesa_droga] Processo de remoção concluído")
end

-- Carregar modelos (clientes e mesa)
Citizen.CreateThread(function()
    for _, model in ipairs(Config.ModelosClientes) do
        local hash = GetHashKey(model)
        RequestModel(hash)
        while not HasModelLoaded(hash) do Citizen.Wait(10) end
    end
    local mesaHash = GetHashKey(Config.MesaModel)
    RequestModel(mesaHash)
    while not HasModelLoaded(mesaHash) do Citizen.Wait(10) end
end)

-- Função para criar mesa com verificações
function CriarMesa(coords, heading)
    if not coords or not heading then 
        print("[mesa_droga] Coordenadas ou heading inválidos")
        return false 
    end
    
    -- Força remoção de qualquer mesa existente primeiro
    if mesaAtiva then
        print("[mesa_droga] Removendo mesa existente antes de criar nova")
        TriggerServerEvent("mesa_droga:remover_mesa_registrada")
        removerMesa()
        -- Aguarda limpeza completa
        Wait(1000)
    end
    
    -- Verifica estado após limpeza
    if mesaAtiva or mesaEntidade then
        print("[mesa_droga] Estado inconsistente após limpeza")
        return false
    end
    
    -- Limpa área antes de criar
    ClearArea(coords.x, coords.y, coords.z, 3.0, true, false, false, false)
    Wait(100)
    
    -- Garante que o modelo está carregado
    local mesaHash = GetHashKey(Config.MesaModel)
    if not IsModelValid(mesaHash) then
        print("[mesa_droga] Modelo inválido:", Config.MesaModel)
        TriggerEvent("Notify", "vermelho", "Modelo da mesa inválido.")
        return false
    end
    
    RequestModel(mesaHash)
    local modelTimeout = GetGameTimer() + 5000
    while not HasModelLoaded(mesaHash) do 
        Wait(10)
        if GetGameTimer() > modelTimeout then
            print("[mesa_droga] Timeout ao carregar modelo")
            return false
        end
    end
    
    -- Cria objeto local
    local object = CreateObject(mesaHash, coords.x, coords.y, coords.z, true, true, false)
    if not object or not DoesEntityExist(object) then
        print("[mesa_droga] Falha ao criar objeto")
        return false
    end
    
    -- Configura objeto local
    SetEntityAsMissionEntity(object, true, true)
    SetEntityCollision(object, true, true)
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)
    SetEntityHeading(object, heading)
    
    -- Solicita registro ao servidor
    local criado = false
    local mesaId = nil
    
    -- Registra eventos uma única vez
    local objetoCriadoHandler = AddEventHandler("mesa_droga:objeto_criado", function(id)
        mesaId = id
        criado = true
    end)
    
    local criacaoFalhouHandler = AddEventHandler("mesa_droga:criacao_falhou", function(motivo)
        print("[mesa_droga] Falha na criação:", motivo)
        criado = false
    end)
    
    -- Solicita criação ao servidor
    TriggerServerEvent("mesa_droga:solicitar_criacao", {
        model = Config.MesaModel,
        coords = coords,
        heading = heading
    })
    
    -- Aguarda resposta do servidor
    local timeout = GetGameTimer() + 5000
    while not criado and GetGameTimer() < timeout do
        Wait(100)
    end
    
    -- Remove handlers
    RemoveEventHandler(objetoCriadoHandler)
    RemoveEventHandler(criacaoFalhouHandler)
    
    if not criado or not mesaId then
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
        print("[mesa_droga] Falha ao registrar mesa no servidor")
        return false
    end
    
    -- Atualiza variáveis globais
    mesaEntidade = object
    mesaCoords = coords
    mesaHeading = heading
    mesaAtiva = true
    mesaAtualId = mesaId
    mesaState = MESA_STATES.ACTIVE
    
    print("[mesa_droga] Mesa criada com sucesso - ID:", mesaId)
    return object
end

-- Função para verificar validade da mesa
local function verificarValidadeMesa(entidade, netId, coords)
    if not entidade or not DoesEntityExist(entidade) then
        print("[mesa_droga] Verificação falhou: entidade não existe")
        return false
    end
    
    if not NetworkGetEntityIsNetworked(entidade) then
        print("[mesa_droga] Verificação falhou: entidade não está networked")
        return false
    end
    
    if not netId or not NetworkDoesNetworkIdExist(netId) then
        print("[mesa_droga] Verificação falhou: netId inválido")
        return false
    end
    
    if not NetworkDoesEntityExistWithNetworkId(netId) then
        print("[mesa_droga] Verificação falhou: netId não corresponde a uma entidade")
        return false
    end
    
    local entityFromNetId = NetworkGetEntityFromNetworkId(netId)
    if entityFromNetId ~= entidade then
        print("[mesa_droga] Verificação falhou: inconsistência entre entidade e netId")
        return false
    end
    
    local currentCoords = GetEntityCoords(entidade)
    if #(currentCoords - coords) > 1.0 then
        print("[mesa_droga] Verificação falhou: posição incorreta")
        return false
    end
    
    -- Tenta obter controle
    if not NetworkHasControlOfEntity(entidade) then
        NetworkRequestControlOfEntity(entidade)
        Wait(500)
        if not NetworkHasControlOfEntity(entidade) then
            print("[mesa_droga] Verificação falhou: não foi possível obter controle")
            return false
        end
    end
    
    return true
end

-- Função para verificar e reparar mesa
function VerificarERepararMesa()
    if not mesaAtiva or not mesaEntidade then return false end
    
    if not DoesEntityExist(mesaEntidade) then return false end
    
    
    local netId = NetworkGetNetworkIdFromEntity(mesaEntidade)
    if not netId or not NetworkDoesNetworkIdExist(netId) then return false end
    
    if not NetworkHasControlOfEntity(mesaEntidade) then
        NetworkRequestControlOfEntity(mesaEntidade)
        Wait(50)
    end
    
    if NetworkHasControlOfEntity(mesaEntidade) then
        SetEntityCoords(mesaEntidade, mesaCoords.x, mesaCoords.y, mesaCoords.z, false, false, false, false)
        SetEntityHeading(mesaEntidade, mesaHeading)
        FreezeEntityPosition(mesaEntidade, true)
        SetEntityCollision(mesaEntidade, true, true)
        SetEntityVisible(mesaEntidade, true, false)
        return true
    end
    
    return false
end

-- Função para limpar mesas próximas
local function limparMesasProximas(coords, raio)
    local mesaHash = GetHashKey(Config.MesaModel)
    local entidadesEncontradas = {}
    
    -- Encontra todas as mesas próximas
    local handle, entity = FindFirstObject()
    local success = true
    
    while success do
        if DoesEntityExist(entity) then
            local model = GetEntityModel(entity)
            if model == mesaHash then
                local entCoords = GetEntityCoords(entity)
                if #(coords - entCoords) <= raio then
                    table.insert(entidadesEncontradas, entity)
                end
            end
        end
        success, entity = FindNextObject(handle)
    end
    
    EndFindObject(handle)
    
    -- Remove todas as mesas encontradas
    for _, ent in ipairs(entidadesEncontradas) do
        if DoesEntityExist(ent) then
            DeleteEntity(ent)
            print("[mesa_droga] Mesa próxima removida")
        end
    end
    
    return #entidadesEncontradas
end

-- Uso da mesa (spawn do objeto)
AddEventHandler("mesa_droga:usar", function()
    if mesaAtiva then
        TriggerEvent("Notify", "vermelho", "Você já possui uma mesa ativa.")
        return
    end

    local success, coords, heading = mesaDroga.ObjectControlling(Config.MesaModel)
    if not success then
        TriggerEvent("Notify", "vermelho", "Posicionamento cancelado.")
        TriggerServerEvent("mesa_droga:devolver_item")
        return
    end

    -- Limpa qualquer mesa existente
    removerMesa()

    -- Cria a mesa na posição escolhida
    local mesaHash = GetHashKey(Config.MesaModel)
    mesaEntidade = CreateObject(mesaHash, coords.x, coords.y, coords.z, true, true, true)
    
    if not mesaEntidade or not DoesEntityExist(mesaEntidade) then
        TriggerEvent("Notify", "vermelho", "Falha ao criar mesa.")
        TriggerServerEvent("mesa_droga:devolver_item")
        return
    end

    -- Configura a mesa
    SetEntityAsMissionEntity(mesaEntidade, true, true)
    PlaceObjectOnGroundProperly(mesaEntidade)
    SetEntityHeading(mesaEntidade, heading)
    FreezeEntityPosition(mesaEntidade, true)
    SetEntityCollision(mesaEntidade, true, true)

    -- Configura networking
    local netId = NetworkGetNetworkIdFromEntity(mesaEntidade)
    if not netId or netId == 0 then
        DeleteEntity(mesaEntidade)
        TriggerEvent("Notify", "vermelho", "NetID inválido.")
        TriggerServerEvent("mesa_droga:devolver_item")
        return
    end

    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, false)

    -- Atualiza variáveis de estado
    mesaInventario = {}
    mesaAtiva = true
    mesaCoords = GetEntityCoords(mesaEntidade)
    mesaHeading = heading

    -- Registra no servidor
    local data = {
        object = Config.MesaModel,
        x = mesaCoords.x,
        y = mesaCoords.y,
        z = mesaCoords.z,
        h = heading,
        Distance = 25.0,
        mode = "5",
        item = "mesa_droga",
        perm = false
    }
    
    TriggerServerEvent("mesa_droga:registrar_objeto", data)
    TriggerServerEvent("mesa_droga:remover_item")
end)

-- Guardar mesa
AddEventHandler("mesa_droga:guardar_mesa", function()
    print("%%%%% [mesa_droga CLIENTE] Evento 'mesa_droga:guardar_mesa' ACIONADO! %%%%%") 
    print("[mesa_droga] Iniciando processo de guardar mesa")

    if not mesaAtiva then
        print("[mesa_droga] Tentativa de guardar mesa sem mesa ativa")
        TriggerEvent("Notify", "vermelho", "Você não tem uma mesa ativa.")
        return
    end
    
    -- Primeiro envia as drogas para o servidor
    if next(mesaInventario) then
        print("[mesa_droga] Devolvendo drogas:", json.encode(mesaInventario))
        TriggerServerEvent("mesa_droga:devolver_drogas", mesaInventario)
    end
    
    -- Remove a mesa física e limpa estados locais
    removerMesa()
    
    -- Por último, notifica o servidor para remover registros
    print("[mesa_droga] Notificando servidor para remover registros")
    TriggerServerEvent("mesa_droga:remover_mesa_registrada")
    
    TriggerEvent("Notify", "verde", "Mesa guardada com sucesso.")
end)

-- Abrir painel de drogas
AddEventHandler("mesa_droga:abrir_painel", function()
    if mesaAtiva then
        print("[mesa_droga] Solicitando inventário para abrir NUI")
        SetNuiFocus(true, true) -- Garante que o foco é definido antes
        TriggerServerEvent("mesa_droga:solicitar_inventario_drogas")
    else
        print("[mesa_droga] Tentativa de abrir NUI sem mesa ativa")
        TriggerEvent("Notify", "vermelho", "Você não tem uma mesa ativa.")
    end
end)

-- Receber inventário para NUI
AddEventHandler("mesa_droga:abrir_nui_com_drogas", function(data)
    if not mesaAtiva then return end
    
    print("[mesa_droga] Abrindo NUI com dados:", json.encode(data))
    SetNuiFocus(true, true)
    SendNUIMessage({ 
        action = "show", 
        mesa = mesaInventario, 
        player = data,
        visible = true -- Garante que a NUI sabe que deve ficar visível
    })
end)

-- Eventos NUI
RegisterNUICallback("fecharMesa", function(_, cb)
    print("[mesa_droga] Fechando NUI")
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "hide" })
    cb("ok")
end)

RegisterNUICallback("adicionarDroga", function(data, cb)
    if data.item and data.quantidade then
        print("[mesa_droga] Adicionando droga:", data.item, "quantidade:", data.quantidade)
        TriggerServerEvent("mesa_droga:adicionar_droga", { item = data.item, quantidade = data.quantidade })
    end
    cb("ok")
end)

-- Atualizar inventário local e spawn NPC imediato
AddEventHandler("mesa_droga:atualizar_droga", function(item, tipo, quantidade)
    quantidade = quantidade or 1
    if tipo == "add" then
        mesaInventario[item] = (mesaInventario[item] or 0) + quantidade
        
        -- Somente atualiza a NUI se não estiver em venda
        if not emVenda then
            SendNUIMessage({ action = "show", mesa = mesaInventario })
        end
        
        -- Força um novo spawn quando drogas são adicionadas
        if not clienteNPC and not aguardandoCliente then
            spawnCliente()
        end
    elseif tipo == "remove" then
        mesaInventario[item] = (mesaInventario[item] or 0) - quantidade
        if mesaInventario[item] <= 0 then mesaInventario[item] = nil end
        
        -- Somente atualiza a NUI se não estiver em venda
        if not emVenda then
            SendNUIMessage({ action = "show", mesa = mesaInventario })
        end
    end
end)

-- Função para spawnar cliente NPC
function spawnCliente()
    print("[mesa_droga CLIENTE] spawnCliente() CHAMADA.")
    if not mesaAtiva or not next(mesaInventario) then 
        print("[mesa_droga CLIENTE] spawnCliente RETORNANDO: mesaNaoAtiva ou semDrogas.")
        return 
    end
    if aguardandoCliente or clienteNPC or npcAtivo then 
        print("[mesa_droga CLIENTE] spawnCliente RETORNANDO: aguardandoCliente OU clienteNPC existente OU npcAtivo.")
        print(string.format("[DEBUG] aguardandoCliente: %s, clienteNPC: %s, npcAtivo: %s", tostring(aguardandoCliente), tostring(clienteNPC), tostring(npcAtivo)))
        return 
    end
    if GetGameTimer() - ultimoSpawnTime < Config.TempoSpawnNPC then 
        print("[mesa_droga CLIENTE] spawnCliente RETORNANDO: Cooldown de spawn.")
        return 
    end
    
    aguardandoCliente = true
    ultimoSpawnTime = GetGameTimer()
    print("[mesa_droga CLIENTE] spawnCliente: Solicitando spawn de NPC ao servidor...")
    TriggerServerEvent("mesa_droga:solicitar_spawn_npc")
end

-- Evento para solicitar novo NPC após remoção
AddEventHandler("mesa_droga:solicitar_novo_npc", function()
    print("%%%%% [mesa_droga CLIENTE] Evento \'mesa_droga:solicitar_novo_npc\' RECEBIDO DO SERVIDOR %%%%%")
    
    -- Limpa estados anteriores
    if clienteNPC and DoesEntityExist(clienteNPC) then
        DeleteEntity(clienteNPC)
    end
    clienteNPC = nil
    aguardandoCliente = false
    npcAtivo = false
    
    -- Verifica condições para spawn
    if not mesaAtiva then
        print("[mesa_droga] Mesa não está ativa para novo NPC")
        return
    end
    
    if not next(mesaInventario) then
        print("[mesa_droga] Sem drogas disponíveis para novo NPC")
        return
    end
    
    -- Força um pequeno delay antes do spawn
    Citizen.SetTimeout(2000, function()
        print("[mesa_droga CLIENTE] Timeout de solicitar_novo_npc EXECUTANDO.")
        if not clienteNPC and not aguardandoCliente and not npcAtivo then
            print("[mesa_droga CLIENTE] Timeout de solicitar_novo_npc: CHAMANDO spawnCliente().")
            spawnCliente()
        else
            print("[mesa_droga CLIENTE] Timeout de solicitar_novo_npc: Spawn cancelado - NPC já existe ou aguardando.")
            print(string.format("[DEBUG] aguardandoCliente: %s, clienteNPC: %s, npcAtivo: %s", tostring(aguardandoCliente), tostring(clienteNPC), tostring(npcAtivo)))
        end
    end)
end)

-- Evento para spawn de NPC sincronizado
AddEventHandler("mesa_droga:spawn_npc_para_todos", function(data)
    print("%%%%% [mesa_droga CLIENTE] Evento \'mesa_droga:spawn_npc_para_todos\' RECEBIDO DO SERVIDOR. MesaID: " .. tostring(data.mesaId) .. "%%%%%")
    Citizen.CreateThread(function()
        print("[mesa_droga CLIENTE] spawn_npc_para_todos: Iniciando spawn de NPC para mesa: " .. tostring(data.mesaId))
        
        -- Limpa NPC anterior se existir
        if npcsSpawnados[data.mesaId] then 
            if DoesEntityExist(npcsSpawnados[data.mesaId]) then
                DeleteEntity(npcsSpawnados[data.mesaId])
            end
            npcsSpawnados[data.mesaId] = nil
            clienteNPC = nil
        end
        
        -- Verifica se a mesa ainda existe
        local mesaObj = GetClosestObjectOfType(data.coords.x, data.coords.y, data.coords.z, 3.0, mesaHash, false, false, false)
        if not mesaObj or not DoesEntityExist(mesaObj) then 
            print("[mesa_droga CLIENTE] spawn_npc_para_todos: Mesa não encontrada para spawn")
            aguardandoCliente = false
            npcAtivo = false
            return 
        end

        -- Carrega o modelo do NPC com retry
        local modelLoaded = false
        local retryCount = 0
        while not modelLoaded and retryCount < 5 do
            modelLoaded = loadModel(data.model)
            if not modelLoaded then
                retryCount = retryCount + 1
                Citizen.Wait(100)
            end
        end

        if not modelLoaded then
            print("[mesa_droga CLIENTE] spawn_npc_para_todos: Falha ao carregar modelo do NPC após " .. retryCount .. " tentativas")
            aguardandoCliente = false
            npcAtivo = false
            return
        end

        -- Calcula posição do spawn
        local spawnPos = GetOffsetFromEntityInWorldCoords(mesaObj, 0.0, Config.DistanciaSpawnNPC, 0.0)
        local x, y, z = spawnPos.x, spawnPos.y, spawnPos.z
        local success, groundZ = GetGroundZFor_3dCoord(x, y, z + 0.5, 0)
        if success then z = groundZ end

        -- Cria e configura o NPC
        local npc = CreatePed(4, GetHashKey(data.model), x, y, z, data.heading + 180.0, false, true)
        if not DoesEntityExist(npc) then
            print("[mesa_droga CLIENTE] spawn_npc_para_todos: Falha ao criar NPC")
            aguardandoCliente = false
            npcAtivo = false
            return
        end

        -- Configurações avançadas do NPC
        SetEntityAsMissionEntity(npc, true, true)
        SetEntityInvincible(npc, true)
        FreezeEntityPosition(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)
        SetPedCanRagdoll(npc, false)
        SetPedCanPlayAmbientAnims(npc, false)
        SetPedConfigFlag(npc, 113, true)
        SetPedConfigFlag(npc, 17, true)
        SetPedConfigFlag(npc, 33, false)
        SetPedConfigFlag(npc, 146, true)
        SetPedFleeAttributes(npc, 0, false)
        SetPedCombatAttributes(npc, 17, true)
        SetPedSeeingRange(npc, 0.0)
        SetPedHearingRange(npc, 0.0)
        SetPedAlertness(npc, 0)
        SetPedKeepTask(npc, true)
        SetEntityLoadCollisionFlag(npc, true)
        SetPedDiesWhenInjured(npc, false)
        
        -- Previne que o NPC seja removido
        SetEntityAsNoLongerNeeded(npc)
        SetModelAsNoLongerNeeded(GetHashKey(data.model))
        NetworkSetEntityInvisibleToNetwork(npc, true)

        -- Carrega e executa animação do NPC
        loadAnimDict(Config.Animacoes.NPC.Dict)
        TaskPlayAnim(npc, Config.Animacoes.NPC.Dict, Config.Animacoes.NPC.Anim, 8.0, -8.0, -1, Config.Animacoes.NPC.Flags, 0, false, false, false)

        -- Registra o NPC
        npcsSpawnados[data.mesaId] = npc
        mesaAtualId = data.mesaId
        clienteNPC = npc
        npcAtivo = true
        
        print("[mesa_droga CLIENTE] spawn_npc_para_todos: NPC spawned com sucesso para mesa: " .. tostring(data.mesaId))
        aguardandoCliente = false
    end)
end)

-- Função para fazer o NPC sair andando
local function npcSairAndando(npc, mesaId)
    print("[mesa_droga CLIENTE] npcSairAndando() CHAMADA para NPC da mesaID: " .. mesaId)
    if not DoesEntityExist(npc) then return end
    
    -- Desbloqueia o NPC mas mantém outras configurações
    FreezeEntityPosition(npc, false)
    SetEntityInvincible(npc, true)
    SetPedCanRagdoll(npc, false)
    
    -- Carrega animação de caminhada
    RequestAnimSet("move_m@drunk@slightlydrunk")
    while not HasAnimSetLoaded("move_m@drunk@slightlydrunk") do
        Citizen.Wait(10)
    end
    SetPedMovementClipset(npc, "move_m@drunk@slightlydrunk", 1.0)
    
    -- Calcula posição final (mais longe para dar tempo da animação)
    local coordsNPC = GetEntityCoords(npc)
    local heading = GetEntityHeading(npc)
    local coordsFinal = GetOffsetFromEntityInWorldCoords(npc, 0.0, 20.0, 0.0)
    
    -- Cria uma task sequence para garantir que todas as animações sejam executadas
    local taskSequence = OpenSequenceTask()
    TaskGoStraightToCoord(0, coordsFinal.x, coordsFinal.y, coordsFinal.z, 1.0, -1, heading, 0.0)
    TaskPause(0, 1000)
    CloseSequenceTask(taskSequence)
    
    -- Aplica a sequência ao NPC
    ClearPedTasks(npc)
    TaskPerformSequence(npc, taskSequence)
    ClearSequenceTask(taskSequence)
    
    -- Monitora o progresso do NPC e remove após completar
    Citizen.CreateThread(function()
        local startTime = GetGameTimer()
        local timeout = false
        
        while DoesEntityExist(npc) do
            Citizen.Wait(100)
            local currentCoords = GetEntityCoords(npc)
            local dist = #(currentCoords - coordsFinal)
            
            -- Verifica se chegou ao destino ou timeout
            if dist < 1.0 or GetGameTimer() - startTime > Config.TempoSaidaNPC then
                -- Fade out do NPC
                local alpha = 255
                while alpha > 0 and DoesEntityExist(npc) do
                    Wait(20)
                    alpha = alpha - 5
                    SetEntityAlpha(npc, alpha, false)
                end
                
                -- Remove o NPC
                if DoesEntityExist(npc) then
                    DeleteEntity(npc)
                end
                
                -- Limpa referências
                if npcsSpawnados[mesaId] == npc then
                    npcsSpawnados[mesaId] = nil
                end
                if clienteNPC == npc then
                    clienteNPC = nil
                end
                npcAtivo = false
                
                -- Agenda próximo spawn -- TEMPORARIAMENTE DESABILITADO PARA TESTE
                -- Citizen.SetTimeout(Config.TempoSpawnNPC, function()
                --     print("[mesa_droga CLIENTE] Timeout de npcSairAndando EXECUTANDO.") 
                --     if not clienteNPC and not aguardandoCliente and not npcAtivo then
                --         print("[mesa_droga CLIENTE] Timeout de npcSairAndando: CHAMANDO spawnCliente().")
                --         spawnCliente()
                --     else
                --         print("[mesa_droga CLIENTE] Timeout de npcSairAndando: Spawn cancelado - NPC já existe ou aguardando.")
                --         print(string.format("[DEBUG] aguardandoCliente: %s, clienteNPC: %s, npcAtivo: %s", tostring(aguardandoCliente), tostring(clienteNPC), tostring(npcAtivo)))
                --     end
                -- end)
                print("[mesa_droga CLIENTE] npcSairAndando: Chamada para spawnCliente() desabilitada para teste.") -- LOG ADICIONADO
                
                break
            end
        end
    end)
end

-- Evento para remover NPC sincronizado
AddEventHandler("mesa_droga:remover_npc_para_todos", function(mesaId)
    print("[mesa_droga] Removendo NPC da mesa: " .. tostring(mesaId))
    if npcsSpawnados[mesaId] then
        local npc = npcsSpawnados[mesaId]
        if DoesEntityExist(npc) then
            npcSairAndando(npc, mesaId)
        else
            npcsSpawnados[mesaId] = nil
            if mesaAtualId == mesaId then
                clienteNPC = nil
                mesaAtualId = nil
            end
            npcAtivo = false
        end
    end
    aguardandoCliente = false
    ultimaVenda = GetGameTimer() -- Atualiza o tempo da última venda
end)

-- Loop de verificação de NPC
Citizen.CreateThread(function()
    -- [[ INÍCIO DO BLOCO COMENTADO PARA TESTE
    -- while true do
    --     Citizen.Wait(1000)
    --     if mesaAtiva and next(mesaInventario) and not clienteNPC and not aguardandoCliente and not npcAtivo then
    --         local tempoDesdeUltimaVenda = GetGameTimer() - ultimaVenda
    --         if tempoDesdeUltimaVenda > Config.TempoEntreVendas then
    --             print("[mesa_droga CLIENTE] Loop de Verificação: CONDIÇÕES ATENDIDAS. CHAMANDO spawnCliente().") 
    --             spawnCliente()
    --         end
    --     end
    -- end
    -- ]] FIM DO BLOCO COMENTADO PARA TESTE
    print("[mesa_droga CLIENTE] Loop de Verificação de NPC (backup spawn) DESABILITADO PARA TESTE.") -- LOG ADICIONADO
end)

-- Thread de venda
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if mesaAtiva and IsControlJustPressed(0, Config.InteractionKey) and not emVenda then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local dist = #(coords - mesaCoords)
            
            if dist <= Config.DistanciaInteracao then
                if clienteNPC and DoesEntityExist(clienteNPC) and npcAtivo then
                    -- Verifica se tem drogas disponíveis
                    local drogaDisponivel = nil
                    local quantidadeDisponivel = 0
                    for droga, quantidade in pairs(mesaInventario) do
                        if quantidade > 0 then
                            drogaDisponivel = droga
                            quantidadeDisponivel = quantidade
                            break
                        end
                    end
                    
                    if not drogaDisponivel then
                        TriggerEvent("Notify", "vermelho", "Não há drogas disponíveis para venda.")
                        return
                    end
                    
                    -- Calcula quantidade aleatória (1, 2, 3 ou 4, limitado pelo disponível)
                    local quantidadePossivel = math.min(4, quantidadeDisponivel)
                    local quantidadeVenda = math.random(1, quantidadePossivel)
                    
                    emVenda = true
                    vendaCooldown = GetGameTimer()
                    ultimaVenda = GetGameTimer()
                    
                    -- Notifica servidor que iniciou venda
                    TriggerServerEvent("mesa_droga:iniciar_venda", mesaAtualId)
                    
                    -- Carrega animação de venda
                    loadAnimDict(Config.Animacoes.Venda.Dict)
                    
                    -- Executa animações
                    local speed = Config.Animacoes.Venda.Speed
                    TaskPlayAnim(ped, Config.Animacoes.Venda.Dict, Config.Animacoes.Venda.Anim, 
                        speed, -speed, Config.TempoVenda, Config.Animacoes.Venda.Flags, 0, false, false, false)
                    TaskPlayAnim(clienteNPC, Config.Animacoes.Venda.Dict, Config.Animacoes.Venda.Anim, 
                        speed, -speed, Config.TempoVenda, Config.Animacoes.Venda.Flags, 0, false, false, false)
                    
                    -- Processa venda
                    Citizen.Wait(Config.TempoVenda / 2)
                    TriggerServerEvent("mesa_droga:pagar", drogaDisponivel, quantidadeVenda)
                    TriggerServerEvent("mesa_droga:atualizar_droga", drogaDisponivel, "remove", quantidadeVenda)
                    
                    -- Finaliza venda
                    Citizen.Wait(Config.TempoVenda / 2)
                    emVenda = false
                else
                    TriggerEvent("Notify", "vermelho", "Não há cliente disponível.")
                end
            else
                TriggerEvent("Notify", "vermelho", "Você está muito longe da mesa.")
            end
        end
    end
end)

-- Thread para manter modelos carregados
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000) -- Verifica a cada 5 segundos
        for _, model in ipairs(Config.ModelosClientes) do
            if not HasModelLoaded(GetHashKey(model)) then
                RequestModel(GetHashKey(model))
            end
        end
    end
end)

-- Evento para receber a tabela de objetos
AddEventHandler("objects:Table", function(objetos)
    print("[mesa_droga] Recebendo tabela de objetos do servidor")
    for id, data in pairs(objetos) do
        if data.object == Config.MesaModel then
            print("[mesa_droga] Mesa encontrada - ID:", id)
        end
    end
end)

-- Evento para adicionar objeto
AddEventHandler("objects:Adicionar", function(id, data)
    print("[mesa_droga] Recebendo novo objeto - ID:", id, "Tipo:", data.object)
    
    -- Verifica se é uma mesa de drogas
    if data.object == Config.MesaModel then
        -- Se este cliente já tem uma mesa ativa, ignora.
        if mesaAtiva and mesaEntidade and DoesEntityExist(mesaEntidade) then
            -- Se o ID do objeto recebido for diferente da nossa mesa ativa, ignora (é de outro player).
            -- Se for o mesmo ID, também podemos ignorar pois já a temos.
            if mesaAtualId ~= id then
                print("[mesa_droga] Evento objects:Adicionar para mesa de outro jogador ou já temos uma. Ignorando ID: " .. id)
                return
            else
                 print("[mesa_droga] Evento objects:Adicionar para nossa própria mesa que já existe. Ignorando ID: " .. id)
                return
            end
        end
        
        -- Se não temos uma mesa ativa, mas este evento é para uma mesa que não seria a nossa
        -- (por exemplo, se o servidor estivesse tentando nos dar uma mesa de outro player diretamente aqui),
        -- precisaríamos de uma forma de verificar a propriedade. 
        -- No entanto, o fluxo normal é o jogador usar o item, e o servidor registrar com o source do jogador.
        -- Este evento 'objects:Adicionar' parece ser mais para sincronização geral de objetos.
        -- Vamos assumir que se chegamos aqui sem uma mesaAtiva, e é uma mesa, podemos tentar criá-la
        -- como uma mesa 'observada', mas o CriarMesa atual já lida com o registro no servidor
        -- e define mesaAtiva. Isso pode causar problemas se o evento for de outra pessoa.

        -- Para simplificar e evitar o erro: se já temos uma mesa, não fazemos nada.
        -- Se não temos, e o evento é de uma mesa, a função CriarMesa vai tentar configurar e registrar.
        -- O problema original era 'mesasAtivas' sendo nil. 
        -- A lógica de verificar se a mesa pertence a este jogador precisa ser robusta.
        -- Por agora, vamos focar em remover o erro e manter o comportamento mais próximo do original
        -- assumindo que CriarMesa será chamada e o servidor validará a propriedade.

        print("[mesa_droga] Tentando criar/sincronizar mesa via objects:Adicionar - ID:", id)
        -- A função CriarMesa já tem lógicas para remover mesa existente e tentar criar uma nova.
        -- Se o 'id' aqui é o ID global da mesa, CriarMesa pode precisar ser ajustada para aceitá-lo
        -- ou o servidor não deve enviar este evento para o dono da mesa que já a criou.
        -- Dado o log original, este evento vem DEPOIS do jogador já ter colocado a mesa.
        
        -- Se o evento 'objects:Adicionar' é para a mesa que o próprio jogador está criando,
        -- o sistema de 'mesaAtualId' deve ser usado.
        -- Se 'mesaAtualId' já está definido e é igual a 'id', não faz nada.
        if mesaAtualId == id and mesaAtiva then
            print("[mesa_droga] Mesa (ID: "..id..") já é a nossa mesa ativa. Ignorando objects:Adicionar.")
            return
        end

        -- Se não temos mesa ativa, e este evento chega, pode ser a sincronização inicial.
        if not mesaAtiva then
             print("[mesa_droga] Nenhuma mesa ativa, processando objects:Adicionar para ID: " .. id)
             CriarMesa(vector3(data.x, data.y, data.z), data.h) 
             -- Após CriarMesa, mesaAtualId será definido se a criação for bem-sucedida para este jogador.
        else
            print("[mesa_droga] Temos uma mesa ativa (ID: "..tostring(mesaAtualId).."), mas objects:Adicionar é para ID: "..id..". Ignorando.")
        end
    end
end)

-- Eventos de sincronização da mesa
AddEventHandler("mesa_droga:sincronizar_mesa", function(data)
    if data.netId then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if entity and DoesEntityExist(entity) then
            -- Atualiza configurações da entidade
            SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
            SetEntityHeading(entity, data.heading)
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, true, true)
        end
    end
end)

AddEventHandler("mesa_droga:registro_confirmado", function(id)
    print("[mesa_droga] Registro da mesa confirmado com ID: " .. id)
    -- Aqui podemos adicionar lógica adicional após confirmação do registro
end)

-- Evento para remover mesa
AddEventHandler("mesa_droga:remover_mesa", function(mesaId)
    print("[mesa_droga] Recebido evento para remover mesa - ID:", mesaId)
    
    -- Verifica se é a nossa mesa
    if mesaAtualId == mesaId then
        print("[mesa_droga] Removendo mesa local - ID:", mesaId)
        
        -- Força remoção da entidade
        if mesaEntidade and DoesEntityExist(mesaEntidade) then
            -- Garante que temos controle da entidade
            if not NetworkHasControlOfEntity(mesaEntidade) then
                NetworkRequestControlOfEntity(mesaEntidade)
                Wait(100)
            end
            
            -- Força remoção
            SetEntityAsMissionEntity(mesaEntidade, true, true)
            DeleteEntity(mesaEntidade)
            
            -- Verifica se foi realmente removida
            if DoesEntityExist(mesaEntidade) then
                print("[mesa_droga] Falha na primeira tentativa, tentando novamente")
                SetEntityCoords(mesaEntidade, 0.0, 0.0, 0.0)
                DeleteEntity(mesaEntidade)
            end
        end
        
        -- Limpa estados locais
        limparEstadoMesa()
    else
        -- Se não for nossa mesa, tenta encontrar a mesa próxima usando coordenadas atuais do jogador
        local playerCoords = GetEntityCoords(PlayerPedId())
        local mesaHash = GetHashKey(Config.MesaModel)
        local mesa = GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, 10.0, mesaHash, false, false, false)
        if mesa and DoesEntityExist(mesa) then
            DeleteEntity(mesa)
        end
    end
end)

-- Thread de sincronização periódica
Citizen.CreateThread(function()
    while true do
        Wait(5000) -- Sincroniza a cada 5 segundos
        if mesaAtiva and mesaEntidade and DoesEntityExist(mesaEntidade) then
            local coords = GetEntityCoords(mesaEntidade)
            local heading = GetEntityHeading(mesaEntidade)
            local netId = NetworkGetNetworkIdFromEntity(mesaEntidade)
            
            -- Envia status atual para o servidor
            TriggerServerEvent("mesa_droga:sync_status", mesaAtualId, {
                coords = coords,
                heading = heading,
                netId = netId,
                exists = true,
                frozen = IsEntityPositionFrozen(mesaEntidade),
                hasNetworking = NetworkGetEntityIsNetworked(mesaEntidade)
            })
        end
    end
end)

-- Evento para recriar mesa
AddEventHandler("mesa_droga:recriar_mesa", function(data)
    if mesaAtiva then
        print("[mesa_droga] Recebendo solicitação de recriação - ID:", data.id)
        
        -- Verifica se a mesa atual ainda existe
        if mesaEntidade and DoesEntityExist(mesaEntidade) then
            local currentNetId = NetworkGetNetworkIdFromEntity(mesaEntidade)
            if currentNetId and NetworkDoesNetworkIdExist(currentNetId) then
                -- Mesa ainda existe e está válida, não precisa recriar
                print("[mesa_droga] Mesa atual ainda válida, ignorando recriação")
                return
            end
            DeleteEntity(mesaEntidade)
        end
        
        -- Tenta recriar a mesa
        local novaMesa = CriarMesa(data.coords, data.heading)
        if novaMesa then
            mesaEntidade = novaMesa
            mesaCoords = data.coords
            mesaHeading = data.heading
            
            -- Atualiza registro no servidor
            TriggerServerEvent("mesa_droga:atualizar_registro", {
                id = data.id,
                netId = NetworkGetNetworkIdFromEntity(novaMesa)
            })
            
            print("[mesa_droga] Mesa recriada com sucesso - ID:", data.id)
        else
            print("[mesa_droga] Falha ao recriar mesa - ID:", data.id)
            TriggerEvent("Notify", "vermelho", "Falha ao recriar mesa.")
            TriggerServerEvent("mesa_droga:devolver_item")
            removerMesa()
        end
    end
end)

-- Evento para sincronização de mesa
AddEventHandler("mesa_droga:sync_mesa", function(data)
    if not mesaAtiva or not mesaEntidade then return end
    
    if data.netId then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if entity and DoesEntityExist(entity) then
            -- Atualiza configurações
            SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
            SetEntityHeading(entity, data.heading)
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, true, true)
            
            -- Atualiza referências locais
            mesaEntidade = entity
            mesaCoords = data.coords
            mesaHeading = data.heading
        end
    end
end)

-- Evento para sincronização da criação da mesa
AddEventHandler("mesa_droga:sync_creation_response", function(data)
    if not mesaAtiva or not mesaEntidade then return end
    
    local entity = NetworkGetEntityFromNetworkId(data.netId)
    if entity and DoesEntityExist(entity) then
        -- Força configurações corretas
        SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
        SetEntityHeading(entity, data.heading)
        FreezeEntityPosition(entity, true)
        SetEntityCollision(entity, true, true)
        SetEntityInvincible(entity, true)
        SetEntityProofs(entity, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, false, false, false)
        
        if Config.PhysicsConfig.PlaceOnGround then
            PlaceObjectOnGroundProperly(entity)
        end

        -- Delay para estabilização da física
        Citizen.Wait(Config.PhysicsConfig.StabilizationDelay or 500) -- Usar config com fallback

        local netId = NetworkGetNetworkIdFromEntity(entity)
        if not netId or netId == 0 then
            print("[mesa_droga] Falha ao obter netId após criação")
            return
        end
        
        -- Força networking
        NetworkRegisterEntityAsNetworked(entity)
        SetNetworkIdExistsOnAllMachines(netId, true)
        NetworkSetNetworkIdDynamic(netId, false)
        SetNetworkIdCanMigrate(netId, false)
        
        print("[mesa_droga] Mesa sincronizada após criação - NetID:", netId)
    end
end)
