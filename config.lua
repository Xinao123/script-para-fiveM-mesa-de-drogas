Config = {}

Config.Drogas = {
    ["weedsack"] = 500,
    ["cocaine"] = 500,
    ["methsack"] = 500
}
Config.MaxDrogasPorVenda = 4

Config.TempoVenda = 5000
Config.TempoSpawnNPC = 500
Config.TempoTimeoutNPC = 5000
Config.TempoEntreVendas = 500
Config.TempoSaidaNPC = 5000

Config.IntervaloSincronizacao = 1000
Config.TempoMaximoSemSync = 300
Config.TentativasMaximasRecriacao = 3
Config.IntervaloVerificacaoMesa = 1000

Config.MesaModel = "bkr_prop_weed_table_01a"
Config.ModelosClientes = {
    "a_m_m_business_01",
    "a_m_y_business_01",
    "a_m_m_socenlat_01",
    "a_m_y_mexthug_01",
    "s_m_y_dealer_01",
    "mp_m_cocaine_01",
    "a_m_y_downtown_01",
    "a_m_y_smartcaspat_01"
}

Config.InteractionKey = 303
Config.MaxTables = 10

Config.DistanciaSpawnNPC = 1.8
Config.DistanciaInteracao = 3.0
Config.DistanciaSincronizacao = 150.0

Config.ChanceAlertaPolicial = 27
Config.TempoWanted = 300

Config.Debug = {
    LogarSpawns = true,
    LogarVendas = true,
    LogarErros = true,
    LogarSincronizacao = true,
    LogarRecriacao = true
}

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

Config.NetworkConfig = {
    ForceNetworking = true,
    DisableMigration = true,
    ExistsOnAllMachines = true,
    DynamicNetworking = false,
    MaxRetries = 3,
    RetryDelay = 500,
    InitialCheckTime = 5000,
    CheckInterval = 2000,
    MonitorTime = 30000,
    ControlTimeout = 5000
}

Config.PhysicsConfig = {
    FreezePosition = true,
    EnableCollision = true,
    SetProofs = true,
    PlaceOnGround = true,
    StabilizationDelay = 500
}

function Config.Debug.Log(tipo, mensagem)
    if Config.Debug[tipo] then
        print("[mesa_droga] " .. mensagem)
    end
end

return Config