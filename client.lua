local Tunnel = module("vrp","lib/Tunnel")
local Proxy = module("vrp","lib/Proxy")
vRP = Proxy.getInterface("vRP")

local vRPserver = Tunnel.getInterface("vRP")
local mesaDroga = {}
Tunnel.bindInterface("mesa_droga",mesaDroga)
Proxy.addInterface("mesa_droga",mesaDroga)

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

for _, evento in ipairs(eventosParaRegistrar) do
    RegisterNetEvent(evento)
end

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
local tempoEntreValidacoes = 1000
local ultimaValidacao = 0

local MESA_STATES = {
    NONE = "none",
    CREATING = "creating",
    ACTIVE = "active",
    REMOVING = "removing"
}

local mesaState = MESA_STATES.NONE

Citizen.CreateThread(function()
    mesaHash = GetHashKey(Config.MesaModel)
    RequestModel(mesaHash)
    while not HasModelLoaded(mesaHash) do 
        Wait(10) 
    end
end)

function DwText(Text, Font, x, y, Scale, r, g, b, a)
    SetTextFont(Font)
    SetTextScale(Scale, Scale)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(Text)
    DrawText(x, y)
end

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

local function loadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Citizen.Wait(10)
        end
    end
end

local function loadModel(model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    local startTime = GetGameTimer()
    while not HasModelLoaded(hash) do
        Citizen.Wait(10)
        if GetGameTimer() - startTime > 5000 then
            return false
        end
    end
    return true
end

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
        local NextObject = CreateObject(Model, Coords.x, Coords.y, Coords.z, false, false, false)
        SetEntityHeading(NextObject, Heading)
        SetEntityAlpha(NextObject, 175, false)
        PlaceObjectOnGroundProperly(NextObject)
        SetEntityCollision(NextObject, false, false)
        FreezeEntityPosition(NextObject, true)
        while Progress do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
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
                ObjectCoords = GetEntityCoords(NextObject)
                ObjectHeading = GetEntityHeading(NextObject)
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

local function removerMesa()
    print("[mesa_droga] Iniciando processo de remoção da mesa")
    if mesaEntidade then
        if DoesEntityExist(mesaEntidade) then
            print("[mesa_droga] Tentando remover entidade da mesa")
            if not NetworkHasControlOfEntity(mesaEntidade) then
                print("[mesa_droga] Solicitando controle da entidade")
                NetworkRequestControlOfEntity(mesaEntidade)
                Wait(100)
            end
            local netId = NetworkGetNetworkIdFromEntity(mesaEntidade)
            if netId and netId ~= 0 then
                print("[mesa_droga] Configurando migração do netId:", netId)
                SetNetworkIdCanMigrate(netId, true)
            end
            SetEntityAsMissionEntity(mesaEntidade, true, true)
            DeleteEntity(mesaEntidade)
            if DoesEntityExist(mesaEntidade) then
                print("[mesa_droga] Falha na primeira tentativa, tentando novamente")
                SetEntityCoords(mesaEntidade, 0.0, 0.0, 0.0)
                DeleteEntity(mesaEntidade)
            end
        end
        mesaEntidade = nil
    end
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
    print("[mesa_droga] Limpando UI")
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "hide" })
    limparEstadoMesa()
    print("[mesa_droga] Processo de remoção concluído")
end

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

function CriarMesa(coords, heading)
    if not coords or not heading then 
        print("[mesa_droga] Coordenadas ou heading inválidos")
        return false 
    end
    if mesaAtiva then
        print("[mesa_droga] Removendo mesa existente antes de criar nova")
        TriggerServerEvent("mesa_droga:remover_mesa_registrada")
        removerMesa()
        Wait(1000)
    end
    if mesaAtiva or mesaEntidade then
        print("[mesa_droga] Estado inconsistente após limpeza")
        return false
    end
    ClearArea(coords.x, coords.y, coords.z, 3.0, true, false, false, false)
    Wait(100)
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
    local object = CreateObject(mesaHash, coords.x, coords.y, coords.z, true, true, false)
    if not object or not DoesEntityExist(object) then
        print("[mesa_droga] Falha ao criar objeto")
        return false
    end
    SetEntityAsMissionEntity(object, true, true)
    SetEntityCollision(object, true, true)
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)
    SetEntityHeading(object, heading)
    local criado = false
    local mesaId = nil
    local objetoCriadoHandler = AddEventHandler("mesa_droga:objeto_criado", function(id)
        mesaId = id
        criado = true
    end)
    local criacaoFalhouHandler = AddEventHandler("mesa_droga:criacao_falhou", function(motivo)
        print("[mesa_droga] Falha na criação:", motivo)
        criado = false
    end)
    TriggerServerEvent("mesa_droga:solicitar_criacao", {
        model = Config.MesaModel,
        coords = coords,
        heading = heading
    })
    local timeout = GetGameTimer() + 5000
    while not criado and GetGameTimer() < timeout do
        Wait(100)
    end
    RemoveEventHandler(objetoCriadoHandler)
    RemoveEventHandler(criacaoFalhouHandler)
    if not criado or not mesaId then
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
        print("[mesa_droga] Falha ao registrar mesa no servidor")
        return false
    end
    mesaEntidade = object
    mesaCoords = coords
    mesaHeading = heading
    mesaAtiva = true
    mesaAtualId = mesaId
    mesaState = MESA_STATES.ACTIVE
    print("[mesa_droga] Mesa criada com sucesso - ID:", mesaId)
    return object
end

local function npcSairAndando(npc, mesaId)
    if not DoesEntityExist(npc) then return end
    FreezeEntityPosition(npc, false)
    SetEntityInvincible(npc, true)
    SetPedCanRagdoll(npc, false)

    RequestAnimSet("move_m@drunk@slightlydrunk")
    while not HasAnimSetLoaded("move_m@drunk@slightlydrunk") do
        Citizen.Wait(10)
    end
    SetPedMovementClipset(npc, "move_m@drunk@slightlydrunk", 1.0)

    local coordsNPC = GetEntityCoords(npc)
    local heading = GetEntityHeading(npc)
    local coordsFinal = GetOffsetFromEntityInWorldCoords(npc, 0.0, 20.0, 0.0)

    local taskSequence = OpenSequenceTask()
    TaskGoStraightToCoord(0, coordsFinal.x, coordsFinal.y, coordsFinal.z, 1.0, -1, heading, 0.0)
    TaskPause(0, 1000)
    CloseSequenceTask(taskSequence)

    ClearPedTasks(npc)
    TaskPerformSequence(npc, taskSequence)
    ClearSequenceTask(taskSequence)

    Citizen.CreateThread(function()
        local startTime = GetGameTimer()
        while DoesEntityExist(npc) do
            Citizen.Wait(100)
            local currentCoords = GetEntityCoords(npc)
            local dist = #(currentCoords - coordsFinal)
            if dist < 1.0 or GetGameTimer() - startTime > Config.TempoSaidaNPC then
                local alpha = 255
                while alpha > 0 and DoesEntityExist(npc) do
                    Wait(20)
                    alpha = alpha - 5
                    SetEntityAlpha(npc, alpha, false)
                end
                if DoesEntityExist(npc) then
                    DeleteEntity(npc)
                end
                if npcsSpawnados[mesaId] == npc then
                    npcsSpawnados[mesaId] = nil
                end
                if clienteNPC == npc then
                    clienteNPC = nil
                end
                npcAtivo = false
                break
            end
        end
    end)
end

AddEventHandler("mesa_droga:remover_npc_para_todos", function(mesaId)
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
    ultimaVenda = GetGameTimer()
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if mesaAtiva and IsControlJustPressed(0, Config.InteractionKey) and not emVenda then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local dist = #(coords - mesaCoords)
            if dist <= Config.DistanciaInteracao then
                if clienteNPC and DoesEntityExist(clienteNPC) and npcAtivo then
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
                    local quantidadePossivel = math.min(Config.MaxDrogasPorVenda or 4, quantidadeDisponivel)
                    local quantidadeVenda = math.random(1, quantidadePossivel)
                    emVenda = true
                    vendaCooldown = GetGameTimer()
                    ultimaVenda = GetGameTimer()
                    TriggerServerEvent("mesa_droga:iniciar_venda", mesaAtualId)
                    loadAnimDict(Config.Animacoes.Venda.Dict)
                    local speed = Config.Animacoes.Venda.Speed
                    TaskPlayAnim(ped, Config.Animacoes.Venda.Dict, Config.Animacoes.Venda.Anim, speed, -speed, Config.TempoVenda, Config.Animacoes.Venda.Flags, 0, false, false, false)
                    TaskPlayAnim(clienteNPC, Config.Animacoes.Venda.Dict, Config.Animacoes.Venda.Anim, speed, -speed, Config.TempoVenda, Config.Animacoes.Venda.Flags, 0, false, false, false)
                    Citizen.Wait(Config.TempoVenda / 2)
                    TriggerServerEvent("mesa_droga:pagar", drogaDisponivel, quantidadeVenda)
                    TriggerServerEvent("mesa_droga:atualizar_droga", drogaDisponivel, "remove", quantidadeVenda)
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

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        for _, model in ipairs(Config.ModelosClientes) do
            if not HasModelLoaded(GetHashKey(model)) then
                RequestModel(GetHashKey(model))
            end
        end
    end
end)

AddEventHandler("objects:Table", function(objetos)
    print("[mesa_droga] Recebendo tabela de objetos do servidor")
    for id, data in pairs(objetos) do
        if data.object == Config.MesaModel then
            print("[mesa_droga] Mesa encontrada - ID:", id)
        end
    end
end)

AddEventHandler("objects:Adicionar", function(id, data)
    print("[mesa_droga] Recebendo novo objeto - ID:", id, "Tipo:", data.object)
    if data.object == Config.MesaModel then
        if mesaAtiva and mesaEntidade and DoesEntityExist(mesaEntidade) then
            if mesaAtualId ~= id then
                print("[mesa_droga] Evento objects:Adicionar para mesa de outro jogador ou já temos uma. Ignorando ID: " .. id)
                return
            else
                print("[mesa_droga] Evento objects:Adicionar para nossa própria mesa que já existe. Ignorando ID: " .. id)
                return
            end
        end
        print("[mesa_droga] Tentando criar/sincronizar mesa via objects:Adicionar - ID:", id)
        if mesaAtualId == id and mesaAtiva then
            print("[mesa_droga] Mesa (ID: "..id..") já é a nossa mesa ativa. Ignorando objects:Adicionar.")
            return
        end
        if not mesaAtiva then
            print("[mesa_droga] Nenhuma mesa ativa, processando objects:Adicionar para ID: " .. id)
            CriarMesa(vector3(data.x, data.y, data.z), data.h)
        else
            print("[mesa_droga] Temos uma mesa ativa (ID: "..tostring(mesaAtualId).."), mas objects:Adicionar é para ID: "..id..". Ignorando.")
        end
    end
end)

AddEventHandler("mesa_droga:sincronizar_mesa", function(data)
    if not mesaAtiva or not mesaEntidade then return end
    if data.netId then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if entity and DoesEntityExist(entity) then
            SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
            SetEntityHeading(entity, data.heading)
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, true, true)
            mesaEntidade = entity
            mesaCoords = data.coords
            mesaHeading = data.heading
        end
    end
end)

AddEventHandler("mesa_droga:registro_confirmado", function(id)
    print("[mesa_droga] Registro da mesa confirmado com ID: " .. id)
end)

AddEventHandler("mesa_droga:remover_mesa", function(mesaId)
    print("[mesa_droga] Recebido evento para remover mesa - ID:", mesaId)
    if mesaAtualId == mesaId then
        print("[mesa_droga] Removendo mesa local - ID:", mesaId)
        if mesaEntidade and DoesEntityExist(mesaEntidade) then
            if not NetworkHasControlOfEntity(mesaEntidade) then
                NetworkRequestControlOfEntity(mesaEntidade)
                Wait(100)
            end
            SetEntityAsMissionEntity(mesaEntidade, true, true)
            DeleteEntity(mesaEntidade)
            if DoesEntityExist(mesaEntidade) then
                print("[mesa_droga] Falha na primeira tentativa, tentando novamente")
                SetEntityCoords(mesaEntidade, 0.0, 0.0, 0.0)
                DeleteEntity(mesaEntidade)
            end
        end
        limparEstadoMesa()
    else
        local playerCoords = GetEntityCoords(PlayerPedId())
        local mesaHash = GetHashKey(Config.MesaModel)
        local mesa = GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, 10.0, mesaHash, false, false, false)
        if mesa and DoesEntityExist(mesa) then
            DeleteEntity(mesa)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(5000) 
        if mesaAtiva and mesaEntidade and DoesEntityExist(mesaEntidade) then
            local coords = GetEntityCoords(mesaEntidade)
            local heading = GetEntityHeading(mesaEntidade)
            local netId = NetworkGetNetworkIdFromEntity(mesaEntidade)
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

AddEventHandler("mesa_droga:recriar_mesa", function(data)
    if mesaAtiva then
        print("[mesa_droga] Recebendo solicitação de recriação - ID:", data.id)
        if mesaEntidade and DoesEntityExist(mesaEntidade) then
            local currentNetId = NetworkGetNetworkIdFromEntity(mesaEntidade)
            if currentNetId and NetworkDoesNetworkIdExist(currentNetId) then
                print("[mesa_droga] Mesa atual ainda válida, ignorando recriação")
                return
            end
            DeleteEntity(mesaEntidade)
        end
        local novaMesa = CriarMesa(data.coords, data.heading)
        if novaMesa then
            mesaEntidade = novaMesa
            mesaCoords = data.coords
            mesaHeading = data.heading
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

AddEventHandler("mesa_droga:sync_mesa", function(data)
    if not mesaAtiva or not mesaEntidade then return end
    if data.netId then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if entity and DoesEntityExist(entity) then
            SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
            SetEntityHeading(entity, data.heading)
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, true, true)
            mesaEntidade = entity
            mesaCoords = data.coords
            mesaHeading = data.heading
        end
    end
end)

AddEventHandler("mesa_droga:sync_creation_response", function(data)
    if not mesaAtiva or not mesaEntidade then return end
    local entity = NetworkGetEntityFromNetworkId(data.netId)
    if entity and DoesEntityExist(entity) then
        SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
        SetEntityHeading(entity, data.heading)
        FreezeEntityPosition(entity, true)
        SetEntityCollision(entity, true, true)
        SetEntityInvincible(entity, true)
        SetEntityProofs(entity, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, false, false, false)
        if Config.PhysicsConfig.PlaceOnGround then
            PlaceObjectOnGroundProperly(entity)
        end
        Citizen.Wait(Config.PhysicsConfig.StabilizationDelay or 500)
        local netId = NetworkGetNetworkIdFromEntity(entity)
        if not netId or netId == 0 then
            print("[mesa_droga] Falha ao obter netId após criação")
            return
        end
        NetworkRegisterEntityAsNetworked(entity)
        SetNetworkIdExistsOnAllMachines(netId, true)
        NetworkSetNetworkIdDynamic(netId, false)
        SetNetworkIdCanMigrate(netId, false)
        print("[mesa_droga] Mesa sincronizada após criação - NetID:", netId)
    end
end)
```-- filepath: c:\Users\pedro\Documents\GitHub\script-para-fiveM-mesa-de-drogas\client.lua
local Tunnel = module("vrp","lib/Tunnel")
local Proxy = module("vrp","lib/Proxy")
vRP = Proxy.getInterface("vRP")

local vRPserver = Tunnel.getInterface("vRP")
local mesaDroga = {}
Tunnel.bindInterface("mesa_droga",mesaDroga)
Proxy.addInterface("mesa_droga",mesaDroga)

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

for _, evento in ipairs(eventosParaRegistrar) do
    RegisterNetEvent(evento)
end

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
local tempoEntreValidacoes = 1000
local ultimaValidacao = 0

local MESA_STATES = {
    NONE = "none",
    CREATING = "creating",
    ACTIVE = "active",
    REMOVING = "removing"
}

local mesaState = MESA_STATES.NONE

Citizen.CreateThread(function()
    mesaHash = GetHashKey(Config.MesaModel)
    RequestModel(mesaHash)
    while not HasModelLoaded(mesaHash) do 
        Wait(10) 
    end
end)

function DwText(Text, Font, x, y, Scale, r, g, b, a)
    SetTextFont(Font)
    SetTextScale(Scale, Scale)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(Text)
    DrawText(x, y)
end

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

local function loadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Citizen.Wait(10)
        end
    end
end

local function loadModel(model)
    local hash = GetHashKey(model)
    RequestModel(hash)
    local startTime = GetGameTimer()
    while not HasModelLoaded(hash) do
        Citizen.Wait(10)
        if GetGameTimer() - startTime > 5000 then
            return false
        end
    end
    return true
end

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
        local NextObject = CreateObject(Model, Coords.x, Coords.y, Coords.z, false, false, false)
        SetEntityHeading(NextObject, Heading)
        SetEntityAlpha(NextObject, 175, false)
        PlaceObjectOnGroundProperly(NextObject)
        SetEntityCollision(NextObject, false, false)
        FreezeEntityPosition(NextObject, true)
        while Progress do
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
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
                ObjectCoords = GetEntityCoords(NextObject)
                ObjectHeading = GetEntityHeading(NextObject)
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

local function removerMesa()
    print("[mesa_droga] Iniciando processo de remoção da mesa")
    if mesaEntidade then
        if DoesEntityExist(mesaEntidade) then
            print("[mesa_droga] Tentando remover entidade da mesa")
            if not NetworkHasControlOfEntity(mesaEntidade) then
                print("[mesa_droga] Solicitando controle da entidade")
                NetworkRequestControlOfEntity(mesaEntidade)
                Wait(100)
            end
            local netId = NetworkGetNetworkIdFromEntity(mesaEntidade)
            if netId and netId ~= 0 then
                print("[mesa_droga] Configurando migração do netId:", netId)
                SetNetworkIdCanMigrate(netId, true)
            end
            SetEntityAsMissionEntity(mesaEntidade, true, true)
            DeleteEntity(mesaEntidade)
            if DoesEntityExist(mesaEntidade) then
                print("[mesa_droga] Falha na primeira tentativa, tentando novamente")
                SetEntityCoords(mesaEntidade, 0.0, 0.0, 0.0)
                DeleteEntity(mesaEntidade)
            end
        end
        mesaEntidade = nil
    end
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
    print("[mesa_droga] Limpando UI")
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "hide" })
    limparEstadoMesa()
    print("[mesa_droga] Processo de remoção concluído")
end

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

function CriarMesa(coords, heading)
    if not coords or not heading then 
        print("[mesa_droga] Coordenadas ou heading inválidos")
        return false 
    end
    if mesaAtiva then
        print("[mesa_droga] Removendo mesa existente antes de criar nova")
        TriggerServerEvent("mesa_droga:remover_mesa_registrada")
        removerMesa()
        Wait(1000)
    end
    if mesaAtiva or mesaEntidade then
        print("[mesa_droga] Estado inconsistente após limpeza")
        return false
    end
    ClearArea(coords.x, coords.y, coords.z, 3.0, true, false, false, false)
    Wait(100)
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
    local object = CreateObject(mesaHash, coords.x, coords.y, coords.z, true, true, false)
    if not object or not DoesEntityExist(object) then
        print("[mesa_droga] Falha ao criar objeto")
        return false
    end
    SetEntityAsMissionEntity(object, true, true)
    SetEntityCollision(object, true, true)
    PlaceObjectOnGroundProperly(object)
    FreezeEntityPosition(object, true)
    SetEntityHeading(object, heading)
    local criado = false
    local mesaId = nil
    local objetoCriadoHandler = AddEventHandler("mesa_droga:objeto_criado", function(id)
        mesaId = id
        criado = true
    end)
    local criacaoFalhouHandler = AddEventHandler("mesa_droga:criacao_falhou", function(motivo)
        print("[mesa_droga] Falha na criação:", motivo)
        criado = false
    end)
    TriggerServerEvent("mesa_droga:solicitar_criacao", {
        model = Config.MesaModel,
        coords = coords,
        heading = heading
    })
    local timeout = GetGameTimer() + 5000
    while not criado and GetGameTimer() < timeout do
        Wait(100)
    end
    RemoveEventHandler(objetoCriadoHandler)
    RemoveEventHandler(criacaoFalhouHandler)
    if not criado or not mesaId then
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
        print("[mesa_droga] Falha ao registrar mesa no servidor")
        return false
    end
    mesaEntidade = object
    mesaCoords = coords
    mesaHeading = heading
    mesaAtiva = true
    mesaAtualId = mesaId
    mesaState = MESA_STATES.ACTIVE
    print("[mesa_droga] Mesa criada com sucesso - ID:", mesaId)
    return object
end

local function npcSairAndando(npc, mesaId)
    if not DoesEntityExist(npc) then return end
    FreezeEntityPosition(npc, false)
    SetEntityInvincible(npc, true)
    SetPedCanRagdoll(npc, false)

    RequestAnimSet("move_m@drunk@slightlydrunk")
    while not HasAnimSetLoaded("move_m@drunk@slightlydrunk") do
        Citizen.Wait(10)
    end
    SetPedMovementClipset(npc, "move_m@drunk@slightlydrunk", 1.0)

    local coordsNPC = GetEntityCoords(npc)
    local heading = GetEntityHeading(npc)
    local coordsFinal = GetOffsetFromEntityInWorldCoords(npc, 0.0, 20.0, 0.0)

    local taskSequence = OpenSequenceTask()
    TaskGoStraightToCoord(0, coordsFinal.x, coordsFinal.y, coordsFinal.z, 1.0, -1, heading, 0.0)
    TaskPause(0, 1000)
    CloseSequenceTask(taskSequence)

    ClearPedTasks(npc)
    TaskPerformSequence(npc, taskSequence)
    ClearSequenceTask(taskSequence)

    Citizen.CreateThread(function()
        local startTime = GetGameTimer()
        while DoesEntityExist(npc) do
            Citizen.Wait(100)
            local currentCoords = GetEntityCoords(npc)
            local dist = #(currentCoords - coordsFinal)
            if dist < 1.0 or GetGameTimer() - startTime > Config.TempoSaidaNPC then
                local alpha = 255
                while alpha > 0 and DoesEntityExist(npc) do
                    Wait(20)
                    alpha = alpha - 5
                    SetEntityAlpha(npc, alpha, false)
                end
                if DoesEntityExist(npc) then
                    DeleteEntity(npc)
                end
                if npcsSpawnados[mesaId] == npc then
                    npcsSpawnados[mesaId] = nil
                end
                if clienteNPC == npc then
                    clienteNPC = nil
                end
                npcAtivo = false
                break
            end
        end
    end)
end

AddEventHandler("mesa_droga:remover_npc_para_todos", function(mesaId)
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
    ultimaVenda = GetGameTimer()
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if mesaAtiva and IsControlJustPressed(0, Config.InteractionKey) and not emVenda then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local dist = #(coords - mesaCoords)
            if dist <= Config.DistanciaInteracao then
                if clienteNPC and DoesEntityExist(clienteNPC) and npcAtivo then
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
                    local quantidadePossivel = math.min(Config.MaxDrogasPorVenda or 4, quantidadeDisponivel)
                    local quantidadeVenda = math.random(1, quantidadePossivel)
                    emVenda = true
                    vendaCooldown = GetGameTimer()
                    ultimaVenda = GetGameTimer()
                    TriggerServerEvent("mesa_droga:iniciar_venda", mesaAtualId)
                    loadAnimDict(Config.Animacoes.Venda.Dict)
                    local speed = Config.Animacoes.Venda.Speed
                    TaskPlayAnim(ped, Config.Animacoes.Venda.Dict, Config.Animacoes.Venda.Anim, speed, -speed, Config.TempoVenda, Config.Animacoes.Venda.Flags, 0, false, false, false)
                    TaskPlayAnim(clienteNPC, Config.Animacoes.Venda.Dict, Config.Animacoes.Venda.Anim, speed, -speed, Config.TempoVenda, Config.Animacoes.Venda.Flags, 0, false, false, false)
                    Citizen.Wait(Config.TempoVenda / 2)
                    TriggerServerEvent("mesa_droga:pagar", drogaDisponivel, quantidadeVenda)
                    TriggerServerEvent("mesa_droga:atualizar_droga", drogaDisponivel, "remove", quantidadeVenda)
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

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(5000)
        for _, model in ipairs(Config.ModelosClientes) do
            if not HasModelLoaded(GetHashKey(model)) then
                RequestModel(GetHashKey(model))
            end
        end
    end
end)

AddEventHandler("objects:Table", function(objetos)
    print("[mesa_droga] Recebendo tabela de objetos do servidor")
    for id, data in pairs(objetos) do
        if data.object == Config.MesaModel then
            print("[mesa_droga] Mesa encontrada - ID:", id)
        end
    end
end)

AddEventHandler("objects:Adicionar", function(id, data)
    print("[mesa_droga] Recebendo novo objeto - ID:", id, "Tipo:", data.object)
    if data.object == Config.MesaModel then
        if mesaAtiva and mesaEntidade and DoesEntityExist(mesaEntidade) then
            if mesaAtualId ~= id then
                print("[mesa_droga] Evento objects:Adicionar para mesa de outro jogador ou já temos uma. Ignorando ID: " .. id)
                return
            else
                print("[mesa_droga] Evento objects:Adicionar para nossa própria mesa que já existe. Ignorando ID: " .. id)
                return
            end
        end
        print("[mesa_droga] Tentando criar/sincronizar mesa via objects:Adicionar - ID:", id)
        if mesaAtualId == id and mesaAtiva then
            print("[mesa_droga] Mesa (ID: "..id..") já é a nossa mesa ativa. Ignorando objects:Adicionar.")
            return
        end
        if not mesaAtiva then
            print("[mesa_droga] Nenhuma mesa ativa, processando objects:Adicionar para ID: " .. id)
            CriarMesa(vector3(data.x, data.y, data.z), data.h)
        else
            print("[mesa_droga] Temos uma mesa ativa (ID: "..tostring(mesaAtualId).."), mas objects:Adicionar é para ID: "..id..". Ignorando.")
        end
    end
end)

AddEventHandler("mesa_droga:sincronizar_mesa", function(data)
    if not mesaAtiva or not mesaEntidade then return end
    if data.netId then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if entity and DoesEntityExist(entity) then
            SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
            SetEntityHeading(entity, data.heading)
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, true, true)
            mesaEntidade = entity
            mesaCoords = data.coords
            mesaHeading = data.heading
        end
    end
end)

AddEventHandler("mesa_droga:registro_confirmado", function(id)
    print("[mesa_droga] Registro da mesa confirmado com ID: " .. id)
end)

AddEventHandler("mesa_droga:remover_mesa", function(mesaId)
    print("[mesa_droga] Recebido evento para remover mesa - ID:", mesaId)
    if mesaAtualId == mesaId then
        print("[mesa_droga] Removendo mesa local - ID:", mesaId)
        if mesaEntidade and DoesEntityExist(mesaEntidade) then
            if not NetworkHasControlOfEntity(mesaEntidade) then
                NetworkRequestControlOfEntity(mesaEntidade)
                Wait(100)
            end
            SetEntityAsMissionEntity(mesaEntidade, true, true)
            DeleteEntity(mesaEntidade)
            if DoesEntityExist(mesaEntidade) then
                print("[mesa_droga] Falha na primeira tentativa, tentando novamente")
                SetEntityCoords(mesaEntidade, 0.0, 0.0, 0.0)
                DeleteEntity(mesaEntidade)
            end
        end
        limparEstadoMesa()
    else
        local playerCoords = GetEntityCoords(PlayerPedId())
        local mesaHash = GetHashKey(Config.MesaModel)
        local mesa = GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, 10.0, mesaHash, false, false, false)
        if mesa and DoesEntityExist(mesa) then
            DeleteEntity(mesa)
        end
    end
end)

Citizen.CreateThread(function()
    while true do
        Wait(5000) 
        if mesaAtiva and mesaEntidade and DoesEntityExist(mesaEntidade) then
            local coords = GetEntityCoords(mesaEntidade)
            local heading = GetEntityHeading(mesaEntidade)
            local netId = NetworkGetNetworkIdFromEntity(mesaEntidade)
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

AddEventHandler("mesa_droga:recriar_mesa", function(data)
    if mesaAtiva then
        print("[mesa_droga] Recebendo solicitação de recriação - ID:", data.id)
        if mesaEntidade and DoesEntityExist(mesaEntidade) then
            local currentNetId = NetworkGetNetworkIdFromEntity(mesaEntidade)
            if currentNetId and NetworkDoesNetworkIdExist(currentNetId) then
                print("[mesa_droga] Mesa atual ainda válida, ignorando recriação")
                return
            end
            DeleteEntity(mesaEntidade)
        end
        local novaMesa = CriarMesa(data.coords, data.heading)
        if novaMesa then
            mesaEntidade = novaMesa
            mesaCoords = data.coords
            mesaHeading = data.heading
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

AddEventHandler("mesa_droga:sync_mesa", function(data)
    if not mesaAtiva or not mesaEntidade then return end
    if data.netId then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if entity and DoesEntityExist(entity) then
            SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
            SetEntityHeading(entity, data.heading)
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, true, true)
            mesaEntidade = entity
            mesaCoords = data.coords
            mesaHeading = data.heading
        end
    end
end)

AddEventHandler("mesa_droga:sync_creation_response", function(data)
    if not mesaAtiva or not mesaEntidade then return end
    local entity = NetworkGetEntityFromNetworkId(data.netId)
    if entity and DoesEntityExist(entity) then
        SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
        SetEntityHeading(entity, data.heading)
        FreezeEntityPosition(entity, true)
        SetEntityCollision(entity, true, true)
        SetEntityInvincible(entity, true)
        SetEntityProofs(entity, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, Config.PhysicsConfig.SetProofs, false, false, false)
        if Config.PhysicsConfig.PlaceOnGround then
            PlaceObjectOnGroundProperly(entity)
        end
        Citizen.Wait(Config.PhysicsConfig.StabilizationDelay or 500)
        local netId = NetworkGetNetworkIdFromEntity(entity)
        if not netId or netId == 0 then
            print("[mesa_droga] Falha ao obter netId após criação")
            return
        end
        NetworkRegisterEntityAsNetworked(entity)
        SetNetworkIdExistsOnAllMachines(netId, true)
        NetworkSetNetworkIdDynamic(netId, false)
        SetNetworkIdCanMigrate(netId, false)
        print("[mesa_droga] Mesa sincronizada após criação - NetID:", netId)
    end
end)