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

local function limparMesasProximas(coords, raio)
    local mesaHash = GetHashKey(Config.MesaModel)
    local entidadesEncontradas = {}

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

    for _, ent in ipairs(entidadesEncontradas) do
        if DoesEntityExist(ent) then
            DeleteEntity(ent)
            print("[mesa_droga] Mesa próxima removida")
        end
    end

    return #entidadesEncontradas
end

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

    removerMesa()

    local mesaHash = GetHashKey(Config.MesaModel)
    mesaEntidade = CreateObject(mesaHash, coords.x, coords.y, coords.z, true, true, true)
    if not mesaEntidade or not DoesEntityExist(mesaEntidade) then
        TriggerEvent("Notify", "vermelho", "Falha ao criar mesa.")
        TriggerServerEvent("mesa_droga:devolver_item")
        return
    end

    SetEntityAsMissionEntity(mesaEntidade, true, true)
    PlaceObjectOnGroundProperly(mesaEntidade)
    SetEntityHeading(mesaEntidade, heading)
    FreezeEntityPosition(mesaEntidade, true)
    SetEntityCollision(mesaEntidade, true, true)

    local netId = NetworkGetNetworkIdFromEntity(mesaEntidade)
    if not netId or netId == 0 then
        DeleteEntity(mesaEntidade)
        TriggerEvent("Notify", "vermelho", "NetID inválido.")
        TriggerServerEvent("mesa_droga:devolver_item")
        return
    end

    SetNetworkIdExistsOnAllMachines(netId, true)
    SetNetworkIdCanMigrate(netId, false)

    mesaInventario = {}
    mesaAtiva = true
    mesaCoords = GetEntityCoords(mesaEntidade)
    mesaHeading = heading

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

AddEventHandler("mesa_droga:guardar_mesa", function()
    if not mesaAtiva then
        TriggerEvent("Notify", "vermelho", "Você não tem uma mesa ativa.")
        return
    end

    if next(mesaInventario) then
        TriggerServerEvent("mesa_droga:devolver_drogas", mesaInventario)
    end

    removerMesa()
    TriggerServerEvent("mesa_droga:remover_mesa_registrada")
    TriggerEvent("Notify", "verde", "Mesa guardada com sucesso.")
end)

AddEventHandler("mesa_droga:abrir_painel", function()
    if mesaAtiva then
        SetNuiFocus(true, true)
        TriggerServerEvent("mesa_droga:solicitar_inventario_drogas")
    else
        TriggerEvent("Notify", "vermelho", "Você não tem uma mesa ativa.")
    end
end)

AddEventHandler("mesa_droga:abrir_nui_com_drogas", function(data)
    if not mesaAtiva then return end
    SetNuiFocus(true, true)
    SendNUIMessage({ action = "show", mesa = mesaInventario, player = data, visible = true })
end)

RegisterNUICallback("fecharMesa", function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "hide" })
    cb("ok")
end)

RegisterNUICallback("adicionarDroga", function(data, cb)
    if data.item and data.quantidade then
        TriggerServerEvent("mesa_droga:adicionar_droga", { item = data.item, quantidade = data.quantidade })
    end
    cb("ok")
end)

AddEventHandler("mesa_droga:atualizar_droga", function(item, tipo, quantidade)
    quantidade = quantidade or 1
    if tipo == "add" then
        mesaInventario[item] = (mesaInventario[item] or 0) + quantidade
        if not emVenda then
            SendNUIMessage({ action = "show", mesa = mesaInventario })
        end
        if not clienteNPC and not aguardandoCliente then
            spawnCliente()
        end
    elseif tipo == "remove" then
        mesaInventario[item] = (mesaInventario[item] or 0) - quantidade
        if mesaInventario[item] <= 0 then mesaInventario[item] = nil end
        if not emVenda then
            SendNUIMessage({ action = "show", mesa = mesaInventario })
        end
    end
end)

function spawnCliente()
    if not mesaAtiva or not next(mesaInventario) then return end
    if aguardandoCliente or clienteNPC or npcAtivo then return end
    if GetGameTimer() - ultimoSpawnTime < Config.TempoSpawnNPC then return end

    aguardandoCliente = true
    ultimoSpawnTime = GetGameTimer()
    TriggerServerEvent("mesa_droga:solicitar_spawn_npc")
end

AddEventHandler("mesa_droga:solicitar_novo_npc", function()
    if clienteNPC and DoesEntityExist(clienteNPC) then
        DeleteEntity(clienteNPC)
    end
    clienteNPC = nil
    aguardandoCliente = false
    npcAtivo = false

    if not mesaAtiva then return end
    if not next(mesaInventario) then return end

    Citizen.SetTimeout(2000, function()
        if not clienteNPC and not aguardandoCliente and not npcAtivo then
            spawnCliente()
        end
    end)
end)

AddEventHandler("mesa_droga:spawn_npc_para_todos", function(data)
    Citizen.CreateThread(function()
        if npcsSpawnados[data.mesaId] then
            if DoesEntityExist(npcsSpawnados[data.mesaId]) then
                DeleteEntity(npcsSpawnados[data.mesaId])
            end
            npcsSpawnados[data.mesaId] = nil
            clienteNPC = nil
        end

        local mesaObj = GetClosestObjectOfType(data.coords.x, data.coords.y, data.coords.z, 3.0, mesaHash, false, false, false)
        if not mesaObj or not DoesEntityExist(mesaObj) then
            aguardandoCliente = false
            npcAtivo = false
            return
        end

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
            aguardandoCliente = false
            npcAtivo = false
            return
        end

        local spawnPos = GetOffsetFromEntityInWorldCoords(mesaObj, 0.0, Config.DistanciaSpawnNPC, 0.0)
        local x, y, z = spawnPos.x, spawnPos.y, spawnPos.z
        local success, groundZ = GetGroundZFor_3dCoord(x, y, z + 0.5, 0)
        if success then z = groundZ end

        local npc = CreatePed(4, GetHashKey(data.model), x, y, z, data.heading + 180.0, false, true)
        if not DoesEntityExist(npc) then
            aguardandoCliente = false
            npcAtivo = false
            return
        end

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

        SetEntityAsNoLongerNeeded(npc)
        SetModelAsNoLongerNeeded(GetHashKey(data.model))
        NetworkSetEntityInvisibleToNetwork(npc, true)

        loadAnimDict(Config.Animacoes.NPC.Dict)
        TaskPlayAnim(npc, Config.Animacoes.NPC.Dict, Config.Animacoes.NPC.Anim, 8.0, -8.0, -1, Config.Animacoes.NPC.Flags, 0, false, false, false)

        npcsSpawnados[data.mesaId] = npc
        mesaAtualId = data.mesaId
        clienteNPC = npc
        npcAtivo = true
        aguardandoCliente = false
    end)
end)

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
                print("[mesa_droga CLIENTE] npcSairAndando: Chamada para spawnCliente() desabilitada para teste.")
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
    -- backup spawn loop desabilitado
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
                    local quantidadePossivel = math.min(4, quantidadeDisponivel)
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
    for id, data in pairs(objetos) do
        if data.object == Config.MesaModel then
            print("[mesa_droga] Mesa encontrada - ID:", id)
        end
    end
end)

AddEventHandler("objects:Adicionar", function(id, data)
    if data.object == Config.MesaModel then
        if mesaAtiva and mesaEntidade and DoesEntityExist(mesaEntidade) then
            if mesaAtualId ~= id then
                return
            else
                return
            end
        end
        if mesaAtualId == id and mesaAtiva then
            return
        end
        if not mesaAtiva then
            CriarMesa(vector3(data.x, data.y, data.z), data.h)
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
    if mesaAtualId == mesaId then
        if mesaEntidade and DoesEntityExist(mesaEntidade) then
            if not NetworkHasControlOfEntity(mesaEntidade) then
                NetworkRequestControlOfEntity(mesaEntidade)
                Wait(100)
            end
            SetEntityAsMissionEntity(mesaEntidade, true, true)
            DeleteEntity(mesaEntidade)
            if DoesEntityExist(mesaEntidade) then
                SetEntityCoords(mesaEntidade, 0.0, 0.0, 0.0)
                DeleteEntity(mesaEntidade)
            end
        end
        limparEstadoMesa()
    else
        local playerCoords = GetEntityCoords(PlayerPedId())
        local mesaHashLocal = GetHashKey(Config.MesaModel)
        local mesa = GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, 10.0, mesaHashLocal, false, false, false)
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
        if mesaEntidade and DoesEntityExist(mesaEntidade) then
            local currentNetId = NetworkGetNetworkIdFromEntity(mesaEntidade)
            if currentNetId and NetworkDoesNetworkIdExist(currentNetId) then
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
        else
            TriggerEvent("Notify", "vermelho", "Falha ao recriar mesa.")
            TriggerServerEvent("mesa_droga:devolver_item")
            removerMesa()
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
                    -- Processa venda
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

-- Evento para receber a tabela de objetos
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
    if data.netId then
        local entity = NetworkGetEntityFromNetworkId(data.netId)
        if entity and DoesEntityExist(entity) then
            SetEntityCoords(entity, data.coords.x, data.coords.y, data.coords.z, false, false, false, false)
            SetEntityHeading(entity, data.heading)
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, true, true)
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
