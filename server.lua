local Tunnel = module("vrp", "lib/Tunnel")
local Proxy = module("vrp", "lib/Proxy")
vRP = Proxy.getInterface("vRP")

-- Carrega configurações
local Config = module("mesa_droga", "config")

-- Estados possíveis para NPCs
local NPC_STATES = {
    NONE = "none",
    SPAWNING = "spawning",
    ACTIVE = "active",
    SELLING = "selling",
    DESPAWNING = "despawning"
}

-- Registra eventos como seguros para rede
RegisterNetEvent("mesa_droga:objeto_criado", function() end)
RegisterNetEvent("mesa_droga:criacao_falhou", function() end)
RegisterNetEvent("mesa_droga:sincronizar_mesa", function() end)
RegisterNetEvent("mesa_droga:validar_mesa", function() end)
RegisterNetEvent("mesa_droga:atualizar_estado", function() end)

-- Eventos que precisam ser seguros para rede
local eventosRede = {
    "mesa_droga:objeto_criado",
    "mesa_droga:criacao_falhou",
    "mesa_droga:sincronizar_mesa",
    "mesa_droga:validar_mesa",
    "mesa_droga:atualizar_estado",
    "mesa_droga:remover_mesa",
    "mesa_droga:mesa_validada",
    "mesa_droga:remover_mesa_registrada",
    "mesa_droga:sync_mesa",
    "mesa_droga:update_position",
    "mesa_droga:solicitar_novo_npc",
    "mesa_droga:spawn_npc_para_todos",
    "mesa_droga:remover_npc_para_todos"
}

-- Registra todos os eventos como seguros
for _, evento in ipairs(eventosRede) do
    RegisterNetEvent(evento)
    AddEventHandler(evento, function() end)
end

local objetosRegistrados = {}
local mesasAtivas = {}
local mesasNPCs = {}

-- Estados possíveis para mesas
local MESA_STATES = {
    CREATING = "creating",
    ACTIVE = "active",
    SYNCING = "syncing",
    REMOVING = "removing"
}

-- Variáveis globais do servidor
local mesasRegistradas = {}
local tempoInatividade = 5 * 60000 -- 5 minutos em ms

-- Função para obter o player source a partir do ID da mesa
local function GetPlayerFromMesaId(mesaId)
    for source, id in pairs(mesasAtivas) do
        if id == mesaId then
            return source
        end
    end
    return nil
end

-- Função para agendar próximo spawn de NPC
local function agendarProximoSpawn(mesaId)
    Config.Debug.Log("LogarSpawns", "[SERVER] agendarProximoSpawn INICIADA para mesa: " .. mesaId)
    Citizen.SetTimeout(Config.TempoSpawnNPC, function() -- Config.TempoSpawnNPC é 0.5s
        if mesasNPCs[mesaId] and mesasNPCs[mesaId].state == NPC_STATES.NONE then
            local source = GetPlayerFromMesaId(mesaId)
            if source then
                Config.Debug.Log("LogarSpawns", "[SERVER] agendarProximoSpawn: Solicitando ao CLIENTE que peça um novo NPC. Source: " .. source .. " Mesa: " .. mesaId)
                TriggerClientEvent("mesa_droga:solicitar_novo_npc", source)
            else
                Config.Debug.Log("LogarErros", "[SERVER] agendarProximoSpawn: Dono da mesa não encontrado. Mesa: " .. mesaId)
            end
        elseif mesasNPCs[mesaId] then
             Config.Debug.Log("LogarErros", "[SERVER] agendarProximoSpawn: Não solicitou novo NPC. Estado do NPC: ".. mesasNPCs[mesaId].state .. " (esperado NONE). Mesa: " .. mesaId)
        else
            Config.Debug.Log("LogarErros", "[SERVER] agendarProximoSpawn: Não solicitou novo NPC. Dados da mesa/NPC não encontrados. Mesa: " .. mesaId)
        end
    end)
end

-- Helper para validar entidade
local function validarEntidade(netId)
    if not netId then return false end
    
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or not DoesEntityExist(entity) then return false end
    
    return true
end

-- Função para registrar mesa no servidor
local function registrarMesa(source, object, coords, heading)
    if not source or not coords then
        print("[mesa_droga] Falha ao registrar mesa: dados inválidos")
        return false
    end
    
    -- Configura estado da entidade
    local passport = vRP.Passport(source)
    local mesaData = {
        owner = passport,
        source = source,
        coords = coords,
        heading = heading,
        lastUpdate = os.time(),
        createTime = os.time(),
        state = MESA_STATES.CREATING,
        failedValidations = 0
    }
    
    -- Gera um ID único para a mesa
    local mesaId = passport .. "_" .. os.time()
    
    mesasRegistradas[mesaId] = mesaData
    mesasAtivas[source] = mesaId
    
    -- Registra nos objetos
    objetosRegistrados[mesaId] = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        h = heading,
        object = object,
        Distance = 25.0,
        mode = "5",
        item = "mesa_droga",
        perm = false
    }
    
    print("[mesa_droga] Mesa registrada com sucesso - ID:", mesaId)
    return mesaId
end

-- Função para limpar registros de mesa
local function limparRegistrosMesa(source)
    -- Encontra e remove todos os registros relacionados ao jogador
    local mesaId = mesasAtivas[source]
    if mesaId then
        print("[mesa_droga] Limpando registros da mesa - Source:", source, "ID:", mesaId)
        
        -- Remove da lista de mesas registradas
        if mesasRegistradas[mesaId] then
            mesasRegistradas[mesaId] = nil
        end
        
        -- Remove da lista de mesas ativas
        mesasAtivas[source] = nil
        
        -- Remove da lista de objetos registrados
        if objetosRegistrados[mesaId] then
            objetosRegistrados[mesaId] = nil
        end
        
        -- Remove NPCs associados
        if mesasNPCs[mesaId] then
            mesasNPCs[mesaId] = nil
        end
        
        print("[mesa_droga] Registros limpos com sucesso")
        return true
    end
    return false
end

-- Função para gerenciar estado do NPC
local function setNPCState(mesaId, newState)
    if not mesasNPCs[mesaId] then
        mesasNPCs[mesaId] = {
            state = NPC_STATES.NONE,
            timeoutHandle = nil,
            lastSpawn = 0,
            lastStateChange = os.time()
        }
    end
    
    local npcData = mesasNPCs[mesaId]
    local oldState = npcData.state -- Guardar estado antigo para referência se necessário
    npcData.state = newState
    npcData.lastStateChange = os.time()
    
    -- Limpa timeout anterior se existir e o estado estiver mudando de ACTIVE
    if npcData.timeoutHandle and oldState == NPC_STATES.ACTIVE and newState ~= NPC_STATES.ACTIVE then
        Config.Debug.Log("LogarSpawns", "[SERVER] Limpando timeout de NPC para mesa: " .. mesaId .. " devido à mudança de estado de ACTIVE para " .. newState)
        ClearTimeout(npcData.timeoutHandle) -- Use ClearTimeout para cancelar um SetTimeout existente
        npcData.timeoutHandle = nil
    end
    
    print("[mesa_droga] Estado do NPC alterado para " .. newState .. " na mesa: " .. mesaId)
    
    -- Define novo timeout baseado no estado
    if newState == NPC_STATES.ACTIVE then
        Config.Debug.Log("LogarSpawns", "[SERVER] Iniciando timeout de " .. Config.TempoTimeoutNPC .. "ms para NPC ATIVO na mesa: " .. mesaId)
        npcData.timeoutHandle = Citizen.SetTimeout(Config.TempoTimeoutNPC, function()
            if mesasNPCs[mesaId] and mesasNPCs[mesaId].state == NPC_STATES.ACTIVE then -- Re-checa se ainda está ACTIVE
                Config.Debug.Log("LogarSpawns", "[SERVER] NPC ATIVO atingiu timeout na mesa: " .. mesaId .. ". Mudando para DESPAWNING.")
                setNPCState(mesaId, NPC_STATES.DESPAWNING)
                TriggerClientEvent("mesa_droga:remover_npc_para_todos", -1, mesaId)

                -- Após cliente remover, define como NONE e agenda o próximo
                Citizen.SetTimeout(1500, function() -- Delay para cliente processar remoção
                    if mesasNPCs[mesaId] then
                         Config.Debug.Log("LogarSpawns", "[SERVER] Timeout do NPC: Definindo estado como NONE para mesa: " .. mesaId)
                        setNPCState(mesaId, NPC_STATES.NONE)
                        Config.Debug.Log("LogarSpawns", "[SERVER] Timeout do NPC: Chamando agendarProximoSpawn para mesa: " .. mesaId)
                        agendarProximoSpawn(mesaId) -- Chama a função que solicita ao cliente para pedir um novo NPC
                    end
                end)
            end
        end)
    end
end

-- Evento de remoção de mesa
RegisterNetEvent("mesa_droga:remover_mesa_registrada")
AddEventHandler("mesa_droga:remover_mesa_registrada", function()
    local source = source
    local mesaId = mesasAtivas[source]
    
    if not mesaId then
        print("[mesa_droga] Tentativa de remover mesa inexistente - Source:", source)
        return
    end
    
    print("[mesa_droga] Iniciando remoção de mesa - ID:", mesaId)
    
    -- Remove NPCs associados primeiro
    if mesasNPCs[mesaId] then
        if mesasNPCs[mesaId].state ~= NPC_STATES.NONE then
            setNPCState(mesaId, NPC_STATES.DESPAWNING)
        end
        TriggerClientEvent("mesa_droga:remover_npc_para_todos", -1, mesaId)
        mesasNPCs[mesaId] = nil
    end
    
    -- Notifica todos os jogadores para remover a mesa
    TriggerClientEvent("mesa_droga:remover_mesa", -1, mesaId)
    
    -- Remove registros
    if mesasRegistradas[mesaId] then
        mesasRegistradas[mesaId] = nil
    end
    
    if objetosRegistrados[mesaId] then
        objetosRegistrados[mesaId] = nil
    end
    
    -- Remove da lista de mesas ativas
    mesasAtivas[source] = nil
    
    print("[mesa_droga] Mesa removida com sucesso - ID:", mesaId)
    
    -- Devolve o item da mesa após limpar tudo
    local Passport = vRP.Passport(source)
    if Passport then
        print("[mesa_droga] Devolvendo item da mesa para jogador:", source)
        vRP.GenerateItem(Passport, "mesa_droga", 1, true)
    end
end)

-- Evento de solicitação de criação
RegisterNetEvent("mesa_droga:solicitar_criacao")
AddEventHandler("mesa_droga:solicitar_criacao", function(data)
    local source = source
    print("[mesa_droga] Recebendo solicitação de criação de mesa do jogador:", source)
    
    -- Validações iniciais
    if not data or not data.coords or not data.model then
        TriggerClientEvent("mesa_droga:criacao_falhou", source, "Dados inválidos")
        return
    end
    
    -- Força limpeza de registros antigos primeiro
    limparRegistrosMesa(source)
    
    -- Pequeno delay para garantir que tudo foi limpo
    Wait(500)
    
    -- Verifica novamente se o jogador já tem uma mesa
    if mesasAtivas[source] then
        TriggerClientEvent("mesa_droga:criacao_falhou", source, "Mesa já existe")
        return
    end
    
    -- Registra mesa
    local mesaId = registrarMesa(source, data.model, data.coords, data.heading)
    if not mesaId then
        TriggerClientEvent("mesa_droga:criacao_falhou", source, "Falha ao registrar mesa")
        return
    end
    
    -- Notifica cliente
    print("[mesa_droga] Mesa criada com sucesso - ID:", mesaId)
    TriggerClientEvent("mesa_droga:objeto_criado", source, mesaId)
    
    -- Propaga para outros jogadores
    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        if tonumber(playerId) ~= source then
            TriggerClientEvent("mesa_droga:sincronizar_mesa", tonumber(playerId), {
                id = mesaId,
                coords = data.coords,
                heading = data.heading
            })
        end
    end
end)

-- Evento de desconexão do jogador
AddEventHandler("playerDropped", function()
    local source = source
    limparRegistrosMesa(source)
end)

-- Evento de validação de mesa
RegisterNetEvent("mesa_droga:validar_mesa")
AddEventHandler("mesa_droga:validar_mesa", function(netId)
    local source = source
    local mesaData = mesasRegistradas[netId]
    
    if not mesaData then
        TriggerClientEvent("mesa_droga:criacao_falhou", source, "Mesa não encontrada")
        return
    end
    
    -- Atualiza estado
    mesaData.state = MESA_STATES.ACTIVE
    mesaData.lastUpdate = os.time()
    mesasRegistradas[netId] = mesaData
    
    -- Confirma validação
    TriggerClientEvent("mesa_droga:mesa_validada", source, netId)
end)

-- Evento de atualização de estado
RegisterNetEvent("mesa_droga:atualizar_estado")
AddEventHandler("mesa_droga:atualizar_estado", function(netId)
    local source = source
    if mesasRegistradas[netId] and mesasRegistradas[netId].source == source then
        mesasRegistradas[netId].lastUpdate = os.time()
    end
end)

-- Função para atualizar última atividade da mesa
local function atualizarAtividadeMesa(netId)
    if mesasRegistradas[netId] then
        mesasRegistradas[netId].lastUpdate = os.time()
    end
end

-- Evento para atualizar estado da mesa
RegisterNetEvent("mesa_droga:atualizar_estado")
AddEventHandler("mesa_droga:atualizar_estado", function(netId, data)
    local source = source
    if mesasRegistradas[netId] and mesasRegistradas[netId].source == source then
        local object = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(object) then
            Entity(object).state.set('tableData', data, true)
            mesasRegistradas[netId].lastUpdate = os.time()
        end
    end
end)

-- Evento para remover mesa
RegisterNetEvent("mesa_droga:remover_mesa")
AddEventHandler("mesa_droga:remover_mesa", function(netId)
    local source = source
    if mesasRegistradas[netId] and mesasRegistradas[netId].source == source then
        local object = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(object) then
            DeleteEntity(object)
        end
        mesasRegistradas[netId] = nil
        mesasAtivas[source] = nil
    end
end)

RegisterServerEvent("mesa_droga:remover_item")
AddEventHandler("mesa_droga:remover_item", function()
    local source = source
    TriggerEvent("inventory:remove", source, "mesa_droga", 1)
end)

RegisterServerEvent("mesa_droga:devolver_item")
AddEventHandler("mesa_droga:devolver_item", function()
    local source = source
    local Passport = vRP.Passport(source)
    if Passport then
        vRP.GenerateItem(Passport, "mesa_droga", 1, true)
    end
end)

RegisterServerEvent("mesa_droga:retirar_droga")
AddEventHandler("mesa_droga:retirar_droga", function(item)
    local source = source
    local Passport = vRP.Passport(source)
    local drogas_validas = { weedsack = true, methsack = true, cocaine = true }
    if not Passport or not drogas_validas[item] then
        TriggerClientEvent("Notify", source, "vermelho", "Falha ao devolver a droga.")
        return
    end

    vRP.GiveItem(Passport, item, 1, true)
    TriggerClientEvent("mesa_droga:atualizar_droga", source, item, "remove")
end)

RegisterServerEvent("mesa_droga:pagar")
AddEventHandler("mesa_droga:pagar", function(item, quantidade)
    local source = source
    local Passport = vRP.Passport(source)
    if not Passport or not Config.Drogas[item] or quantidade < 1 or quantidade > Config.MaxDrogasPorVenda then
        TriggerClientEvent("Notify", source, "vermelho", "Dados inválidos.")
        return
    end

    local mesaId = mesasAtivas[source]
    if not mesaId or not objetosRegistrados[mesaId] then
        TriggerClientEvent("Notify", source, "vermelho", "Mesa não encontrada.")
        return
    end

    local mesaData = objetosRegistrados[mesaId]
    local coords = { x = mesaData.x, y = mesaData.y, z = mesaData.z }

    local preco = Config.Drogas[item]
    vRP.GenerateItem(Passport, "reaissujos", preco * quantidade, true)

    if math.random(100) <= Config.ChanceAlertaPolicial then
        TriggerEvent("Wanted", source, Passport, Config.TempoWanted)
        local requiredPermissions = {"Policia"}
        for _, permission in ipairs(requiredPermissions) do
            local Service = vRP.NumPermission(permission)
            for Passports, Sources in pairs(Service) do
                async(function()
                    TriggerClientEvent("NotifyPush", Sources, { 
                        code = "QTH", 
                        title = "Venda de Drogas", 
                        x = coords.x, 
                        y = coords.y, 
                        z = coords.z, 
                        criminal = "Tráfico de entorpecentes", 
                        time = "Recebido às "..os.date("%H:%M"), 
                        blipColor = 16 
                    })
                end)
            end
        end
    end
end)

-- Função para registrar mesa
RegisterServerEvent("mesa_droga:registrar_objeto")
AddEventHandler("mesa_droga:registrar_objeto", function(data)
    local source = source
    print("[mesa_droga] Tentativa de registro de mesa por player:", source)
    
    -- Verifica se o jogador já tem uma mesa ativa
    if mesasAtivas[source] then
        local mesaId = mesasAtivas[source]
        if objetosRegistrados[mesaId] then
            print("[mesa_droga] Jogador já tem mesa ativa - ID:", mesaId)
            TriggerClientEvent("Notify", source, "vermelho", "Você já tem uma mesa ativa.")
            TriggerClientEvent("mesa_droga:devolver_item", source)
            return
        else
            -- Limpa registro inválido e todos os objetos associados
            print("[mesa_droga] Limpando registro inválido - Source:", source)
            if mesasNPCs[mesaId] then
                mesasNPCs[mesaId] = nil
            end
            mesasAtivas[source] = nil
            -- Notifica todos os jogadores para remover a mesa
            TriggerClientEvent("mesa_droga:remover_mesa", -1, mesaId)
        end
    end
    
    -- Verifica limite de mesas
    local totalMesas = 0
    for _ in pairs(objetosRegistrados) do
        totalMesas = totalMesas + 1
    end
    
    if totalMesas >= Config.MaxTables then
        print("[mesa_droga] Limite de mesas atingido")
        TriggerClientEvent("Notify", source, "vermelho", "Limite de mesas atingido.")
        TriggerClientEvent("mesa_droga:devolver_item", source)
        return
    end
    
    -- Gera ID único para a mesa
    local id = source .. "_" .. os.time()
    print("[mesa_droga] Registrando nova mesa - ID:", id)
    
    objetosRegistrados[id] = data
    mesasAtivas[source] = id
    
    -- Inicializa controle de NPC
    mesasNPCs[id] = {
        state = NPC_STATES.NONE,
        timeoutHandle = nil,
        lastSpawn = 0,
        lastStateChange = os.time()
    }
    
    -- Notifica jogadores próximos
    TriggerClientEvent("objects:Adicionar", -1, id, data)
    
    print("[mesa_droga] Mesa registrada com sucesso - ID:", id)
end)

-- Evento para receber status da mesa
RegisterServerEvent("mesa_droga:sync_status")
AddEventHandler("mesa_droga:sync_status", function(mesaId, status)
    local source = source
    if not mesasRegistradas[mesaId] then return end
    
    -- Atualiza informações
    mesasRegistradas[mesaId].lastUpdate = os.time()
    mesasRegistradas[mesaId].coords = status.coords
    mesasRegistradas[mesaId].heading = status.heading
    
    -- Propaga status para jogadores próximos
    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        if tonumber(playerId) ~= source then
            TriggerClientEvent("mesa_droga:sync_mesa", playerId, {
                id = mesaId,
                coords = status.coords,
                heading = status.heading,
                netId = mesaId
            })
        end
    end
end)

-- Thread de limpeza de mesas inativas
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(60000) -- Verifica a cada minuto
        local tempoAtual = os.time()
        
        for mesaId, mesa in pairs(mesasRegistradas) do
            -- Remove mesas que não são atualizadas há mais de Config.TempoMaximoSemSync segundos
            if tempoAtual - mesa.lastUpdate > Config.TempoMaximoSemSync then
                print("[mesa_droga] Removendo mesa inativa - ID:", mesaId)
                
                -- Notifica jogadores próximos
                local players = GetPlayers()
                for _, player in ipairs(players) do
                    TriggerClientEvent("mesa_droga:remover_mesa", player, mesaId)
                end
                
                -- Remove registros
                mesasRegistradas[mesaId] = nil
                if mesa.owner then
                    mesasAtivas[mesa.owner] = nil
                end
            end
        end
    end
end)

RegisterServerEvent("mesa_droga:solicitar_spawn_npc")
AddEventHandler("mesa_droga:solicitar_spawn_npc", function()
    local source = source
    local mesaId = mesasAtivas[source]
    
    Config.Debug.Log("LogarSpawns", "[SERVER] Recebida solicitação de spawn de NPC do cliente. Source: " .. source .. " MesaID: " .. mesaId)

    if not mesaId or not objetosRegistrados[mesaId] then 
        Config.Debug.Log("LogarErros", "[SERVER] Mesa não encontrada para spawn de NPC. Source: " .. source)
        return 
    end
    
    local npcData = mesasNPCs[mesaId]
    if not npcData then
        Config.Debug.Log("LogarErros", "[SERVER] Dados do NPC não encontrados para mesa: " .. mesaId)
        return
    end
    
    if npcData.state == NPC_STATES.NONE then
        local mesaData = objetosRegistrados[mesaId]
        
        if (os.time() - npcData.lastSpawn) < 2 then -- Cooldown básico para evitar spam de solicitações
            Config.Debug.Log("LogarSpawns", "[SERVER] Cooldown de spawn (2s) ainda ativo para mesa: " .. mesaId)
            return
        end
        
        setNPCState(mesaId, NPC_STATES.SPAWNING)
        Config.Debug.Log("LogarSpawns", "[SERVER] NPC em estado SPAWNING para mesa: " .. mesaId)
        
        local modelIndex = math.random(#Config.ModelosClientes)
        local modelName = Config.ModelosClientes[modelIndex]
        mesasNPCs[mesaId].lastSpawn = os.time()
        
        Config.Debug.Log("LogarSpawns", "[SERVER] Solicitando ao CLIENTE para criar ped NPC com modelo " .. modelName .. " para mesa: " .. mesaId)
        TriggerClientEvent("mesa_droga:spawn_npc_para_todos", -1, {
            mesaId = mesaId,
            coords = {x = mesaData.x, y = mesaData.y, z = mesaData.z},
            heading = mesaData.h,
            model = modelName
        })
        
        -- Mudar para ACTIVE quase imediatamente após notificar o cliente.
        -- O cliente precisa de um momento para criar o ped visualmente.
        -- O Config.TempoSpawnNPC original (500ms) pode ser o timeout para o NPC se nenhuma interação ocorrer.
        Citizen.SetTimeout(100, function() -- Pequeno delay (100ms) para o cliente começar a criar o ped.
            if mesasNPCs[mesaId] and mesasNPCs[mesaId].state == NPC_STATES.SPAWNING then
                setNPCState(mesaId, NPC_STATES.ACTIVE)
                Config.Debug.Log("LogarSpawns", "[SERVER] NPC ATIVADO (estado ACTIVE) para mesa: " .. mesaId .. " após delay de 100ms.")
            elseif mesasNPCs[mesaId] then
                 Config.Debug.Log("LogarSpawns", "[SERVER] NPC NÃO foi para ACTIVE. Estado atual: " .. mesasNPCs[mesaId].state .. " para mesa: " .. mesaId)
            end
        end)
    else
        Config.Debug.Log("LogarErros", "[SERVER] Solicitação de spawn de NPC REJEITADA. Estado atual do NPC: " .. npcData.state .. " (esperado: NONE) para mesa: " .. mesaId)
    end
end)

RegisterServerEvent("mesa_droga:remover_npc")
AddEventHandler("mesa_droga:remover_npc", function(mesaId)
    if mesasNPCs[mesaId] then
        setNPCState(mesaId, NPC_STATES.DESPAWNING)
        
        for _, playerId in ipairs(GetPlayers()) do
            TriggerClientEvent("mesa_droga:remover_npc_para_todos", playerId, mesaId)
        end
        
        -- Agenda próximo spawn usando a nova função
        agendarProximoSpawn(mesaId)
    end
end)

RegisterServerEvent("mesa_droga:iniciar_venda")
AddEventHandler("mesa_droga:iniciar_venda", function(mesaId)
    print("[mesa_droga SERVER] Evento iniciar_venda para mesa: " .. tostring(mesaId))
    if mesasNPCs[mesaId] and mesasNPCs[mesaId].state == NPC_STATES.ACTIVE then
        setNPCState(mesaId, NPC_STATES.SELLING)
        Config.Debug.Log("LogarVendas", "NPC em estado SELLING para mesa: " .. mesaId)
        
        -- Agenda ações após a conclusão da animação de venda
        Citizen.SetTimeout(Config.TempoVenda + 500, function() -- Delay para cobrir animação + um pouco mais
            Config.Debug.Log("LogarVendas", "Timeout pós-venda para mesa: " .. mesaId)
            if mesasNPCs[mesaId] and mesasNPCs[mesaId].state == NPC_STATES.SELLING then -- Re-checa o estado
                
                -- 1. Marca o NPC para despawnar e notifica clientes para removê-lo
                setNPCState(mesaId, NPC_STATES.DESPAWNING)
                Config.Debug.Log("LogarVendas", "NPC em estado DESPAWNING para mesa: " .. mesaId)
                TriggerClientEvent("mesa_droga:remover_npc_para_todos", -1, mesaId)

                -- 2. Após um curto delay para garantir que o cliente processou a remoção,
                --    define o estado como NONE e SOMENTE ENTÃO solicita um novo NPC.
                Citizen.SetTimeout(1500, function() -- Pequeno delay adicional (ex: 1.5 segundos)
                    if mesasNPCs[mesaId] then -- Verifica se a mesa ainda existe e tem dados de NPC
                        Config.Debug.Log("LogarVendas", "Definindo estado do NPC como NONE para mesa: " .. mesaId .. " antes de solicitar novo.")
                        setNPCState(mesaId, NPC_STATES.NONE) -- Fundamental estar NONE
                        
                        local source = GetPlayerFromMesaId(mesaId)
                        if source then
                            Config.Debug.Log("LogarSpawns", "[SERVER] Solicitando ao CLIENTE que peça um novo NPC. Source: " .. source .. " Mesa: " .. mesaId)
                            TriggerClientEvent("mesa_droga:solicitar_novo_npc", source)
                        else
                            Config.Debug.Log("LogarErros", "[SERVER] Dono da mesa não encontrado para solicitar novo NPC. Mesa: " .. mesaId)
                        end
                    else
                        Config.Debug.Log("LogarErros", "[SERVER] Dados da mesa ou NPC não encontrados ao tentar solicitar novo NPC após delay. Mesa: " .. mesaId)
                    end
                end)
            else
                Config.Debug.Log("LogarVendas", "[SERVER] Timeout pós-venda: Estado do NPC não era SELLING. Estado atual: " .. (mesasNPCs[mesaId] and mesasNPCs[mesaId].state or "N/A"))
            end
        end)
    else
        Config.Debug.Log("LogarVendas", "[SERVER] Evento iniciar_venda: Estado do NPC não era ACTIVE. Estado atual: " .. (mesasNPCs[mesaId] and mesasNPCs[mesaId].state or "N/A"))
    end
end)

AddEventHandler("playerConnecting", function(_, _, deferrals)
    local src = source
    TriggerClientEvent("objects:Table", src, objetosRegistrados)
end)

RegisterServerEvent("mesa_droga:solicitar_inventario_drogas")
AddEventHandler("mesa_droga:solicitar_inventario_drogas", function()
    local source = source
    local Passport = vRP.Passport(source)
    if Passport then
        local inventario = vRP.Inventory(Passport)
        local drogas = {}
        local drogas_validas = { weedsack = true, methsack = true, cocaine = true }
        for k, v in pairs(inventario) do
            if drogas_validas[v.item] then
                drogas[v.item] = (drogas[v.item] or 0) + v.amount
            end
        end
        TriggerClientEvent("mesa_droga:abrir_nui_com_drogas", source, drogas)
    end
end)

RegisterServerEvent("mesa_droga:adicionar_droga")
AddEventHandler("mesa_droga:adicionar_droga", function(data)
    local source = source
    local Passport = vRP.Passport(source)
    local drogas_validas = { weedsack = true, methsack = true, cocaine = true }
    if Passport and data.item and drogas_validas[data.item] and tonumber(data.quantidade) then
        local qtd = math.max(1, tonumber(data.quantidade))
        local possui = vRP.InventoryItemAmount(Passport, data.item)
        if type(possui) == "table" then possui = possui[1] or possui.amount or 0 end
        if possui >= qtd then
            vRP.RemoveItem(Passport, data.item, qtd)
            TriggerClientEvent("mesa_droga:atualizar_droga", source, data.item, "add", qtd)
        else
            TriggerClientEvent("Notify", source, "vermelho", "Você não tem essa quantidade.")
        end
    else
        TriggerClientEvent("Notify", source, "vermelho", "Droga inválida ou dados incorretos.")
    end
end)

RegisterServerEvent("mesa_droga:devolver_drogas")
AddEventHandler("mesa_droga:devolver_drogas", function(itens)
    local source = source
    local Passport = vRP.Passport(source)
    if not Passport then return end
    
    print("[mesa_droga] Devolvendo drogas para jogador:", source)
    local drogas_validas = { weedsack = true, methsack = true, cocaine = true }
    
    -- Verifica se há drogas para devolver
    local temDrogas = false
    for item, qtd in pairs(itens) do
        if drogas_validas[item] and tonumber(qtd) and qtd > 0 then
            temDrogas = true
            break
        end
    end
    
    if not temDrogas then
        print("[mesa_droga] Nenhuma droga para devolver")
        return
    end
    
    -- Devolve as drogas
    for item, qtd in pairs(itens) do
        if drogas_validas[item] and tonumber(qtd) and qtd > 0 then
            print("[mesa_droga] Devolvendo", qtd, "x", item)
            vRP.GiveItem(Passport, item, qtd, true)
        end
    end
end)

RegisterServerEvent("mesa_droga:atualizar_droga")
AddEventHandler("mesa_droga:atualizar_droga", function(item, tipo, quantidade)
    local source = source
    local mesaId = mesasAtivas[source]
    
    if not mesaId then return end
    
    -- Registra a operação para debug
    Config.Debug.Log("LogarVendas", "Atualizando inventário de " .. item .. " (" .. tipo .. " " .. quantidade .. ")")
    
    -- Propaga a atualização para o cliente
    TriggerClientEvent("mesa_droga:atualizar_droga", source, item, tipo, quantidade)
end)

-- Adiciona evento de sincronização
RegisterServerEvent("mesa_droga:sync_position")
AddEventHandler("mesa_droga:sync_position", function(syncData)
    local source = source
    local mesaId = mesasAtivas[source]
    
    if not mesaId or not objetosRegistrados[mesaId] then return end
    
    -- Atualiza posição no registro
    local data = objetosRegistrados[mesaId]
    data.x = syncData.coords.x
    data.y = syncData.coords.y
    data.z = syncData.coords.z
    data.h = syncData.heading
    
    -- Notifica outros jogadores apenas se não for uma entidade local
    if not data.local_only then
        local playerList = GetPlayers()
        for _, playerId in ipairs(playerList) do
            if tonumber(playerId) ~= source then
                TriggerClientEvent("mesa_droga:update_position", playerId, mesaId, syncData)
            end
        end
    end
end)

-- Evento para atualizar registro da mesa
RegisterServerEvent("mesa_droga:atualizar_registro")
AddEventHandler("mesa_droga:atualizar_registro", function(data)
    local source = source
    if not data or not data.id then return end
    
    local mesa = mesasRegistradas[data.id]
    if not mesa then return end
    
    -- Verifica se o jogador é o dono da mesa
    if mesa.owner ~= vRP.Passport(source) then return end
    
    -- Atualiza dados da mesa
    mesa.netId = data.netId
    mesa.lastUpdate = os.time()
    if data.coords then
        mesa.coords = data.coords
    end
    if data.heading then
        mesa.heading = data.heading
    end
    
    -- Notifica outros jogadores próximos
    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        if tonumber(playerId) ~= source then
            local playerCoords = GetEntityCoords(GetPlayerPed(playerId))
            if #(playerCoords - vector3(mesa.coords.x, mesa.coords.y, mesa.coords.z)) <= Config.DistanciaSincronizacao then
                TriggerClientEvent("mesa_droga:sincronizar_mesa", playerId, {
                    id = data.id,
                    coords = mesa.coords,
                    heading = mesa.heading,
                    netId = mesa.netId,
                    owner = mesa.owner
                })
            end
        end
    end
    
    print("[mesa_droga] Registro atualizado - ID:", data.id, "NetID:", data.netId)
end)

-- Thread de validação de mesas
Citizen.CreateThread(function()
    while true do
        Wait(5000)  -- Verifica a cada 5 segundos
        
        local tempoAtual = os.time()
        for id, mesa in pairs(mesasRegistradas) do
            -- Verifica última atualização
            if tempoAtual - mesa.lastUpdate > 10 then  -- 10 segundos sem atualização
                mesa.failedValidations = (mesa.failedValidations or 0) + 1
                
                if mesa.failedValidations >= 3 then  -- 3 falhas consecutivas
                    print("[mesa_droga] Mesa removida por inatividade - ID:", id)
                    TriggerClientEvent("mesa_droga:remover_mesa_registrada", mesa.source)
                    TriggerClientEvent("mesa_droga:devolver_item", mesa.source)
                    mesasRegistradas[id] = nil
                    mesasAtivas[mesa.source] = nil
                end
            else
                mesa.failedValidations = 0  -- Reseta contador se mesa está ativa
            end
        end
    end
end)