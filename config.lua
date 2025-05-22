Config = {}

-- Configurações de Drogas
Config.Drogas = {
    ["weedsack"] = 500,
    ["cocaine"] = 500,
    ["methsack"] = 500
}
Config.MaxDrogasPorVenda = 4

-- Configurações de Tempo (em milissegundos)
Config.TempoVenda = 5000
Config.TempoSpawnNPC = 500
Config.TempoTimeoutNPC = 5000
Config.TempoEntreVendas = 500
Config.TempoSaidaNPC = 5000

-- Configurações de Sincronização
Config.IntervaloSincronizacao = 1000 -- Intervalo entre sincronizações (ms)
Config.TempoMaximoSemSync = 300 -- Tempo máximo sem sincronização antes de remover mesa (segundos)
Config.TentativasMaximasRecriacao = 3 -- Número máximo de tentativas de recriar mesa
Config.IntervaloVerificacaoMesa = 1000 -- Intervalo entre verificações da mesa (ms)

-- Configurações de Objetos e NPCs
Config.MesaModel = "bkr_prop_weed_table_01a"
Config.ModelosClientes = {
    "a_m_m_business_01",     -- Homem de negócios (muito estável)
    "a_m_y_business_01",     -- Homem jovem de negócios (estável)
    "a_m_m_socenlat_01",     -- Latino de meia idade (estável)
    "a_m_y_mexthug_01",      -- Jovem mexicano (estável para mesa de drogas)
    "s_m_y_dealer_01",       -- Traficante (perfeito para o contexto da mesa)
    "mp_m_cocaine_01",       -- Relacionado a cocaína (temático)
    "a_m_y_downtown_01",     -- Mantido da lista original
    "a_m_y_smartcaspat_01"   -- Cliente de casino (estável e bem vestido)
}

-- Configurações de Interação
Config.InteractionKey = 303 -- Tecla U
Config.MaxTables = 10 -- Número máximo de mesas ativas no servidor

-- Configurações de Distância
Config.DistanciaSpawnNPC = 1.8
Config.DistanciaInteracao = 3.0
Config.DistanciaSincronizacao = 150.0

-- Configurações de Sistema
Config.ChanceAlertaPolicial = 27 -- Porcentagem de chance de alerta policial
Config.TempoWanted = 300 -- Tempo em segundos que o jogador fica procurado

-- Configurações de Debug
Config.Debug = {
    LogarSpawns = true,
    LogarVendas = true,
    LogarErros = true,
    LogarSincronizacao = true,
    LogarRecriacao = true
}

-- Configurações de Animações
Config.Animacoes = {
    NPC = {
        Dict = "amb@world_human_hang_out_street@male_c@idle_a",
        Anim = "idle_a",
        Flags = 1
    },
    Venda = {
        Dict = "mp_common",
        Anim = "givetake1_a",
        Flags = 0,
        Speed = 8.0
    }
}

-- Configurações de Networking
Config.NetworkConfig = {
    ForceNetworking = true,           -- Força o networking da entidade
    DisableMigration = true,          -- Desabilita migração de rede
    ExistsOnAllMachines = true,       -- Garante que a entidade existe em todas as máquinas
    DynamicNetworking = false,        -- Desabilita networking dinâmico
    MaxRetries = 3,                   -- Número máximo de tentativas de recriar a mesa
    RetryDelay = 500,                 -- Delay entre tentativas (ms)
    InitialCheckTime = 5000,          -- Tempo de verificação inicial (ms)
    CheckInterval = 2000,              -- Intervalo entre verificações (ms)
    MonitorTime = 30000,              -- Tempo de monitoramento da mesa (ms)
    ControlTimeout = 5000             -- Timeout para obter controle da entidade (ms)
}

-- Configurações de Física
Config.PhysicsConfig = {
    FreezePosition = true,            -- Congela posição da mesa
    EnableCollision = true,           -- Habilita colisão
    SetProofs = true,                 -- Torna a mesa imune a danos
    PlaceOnGround = true,             -- Força posicionamento no chão
    StabilizationDelay = 500          -- Delay para estabilização da física (ms)
}

function Config.Debug.Log(tipo, mensagem)
    if Config.Debug[tipo] then
        print("[mesa_droga] " .. mensagem)
    end
end

return Config