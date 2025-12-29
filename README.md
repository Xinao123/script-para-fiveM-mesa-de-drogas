# 💊 Drug Table (vRP) for FiveM
Status: 🧊 Archived (not maintained)

A simple drug table system for FiveM, built on top of vRP.
This repository is archived, so expect outdated patterns and possible incompatibilities.

---

## ⚠️ Project Status (Important)
- Archived: this project is no longer in development and may be outdated.
- Use at your own risk: always verify compatibility with your current FiveM + vRP version before deploying.

---

## 🚀 Quick Install
1. Drop the resource folder inside your gamemode `resources` folder.
2. Add this line to your `server.cfg`:
   ensure script-para-fiveM-mesa-de-drogas
3. Requirement: vRP (declared in fxmanifest.lua).

---

## 🧩 Main Files
- Client
  - client.lua
    Important functions: CriarMesa, mesaDroga.ObjectControlling

- Server
  - server.lua
    Important functions: registrarMesa, agendarProximoSpawn

- Config
  - config.lua
    Main values: Config.Drogas, timers and models

- Manifest
  - fxmanifest.lua

- UI
  - html/index.html
  - html/script.js
  - html/style.css

---

## 🧪 Basic Usage
- Adjust settings in config.lua.
- Start/restart the resource on your server.
- Use the item `mesa_droga` to create the table (expects integration with a vRP inventory system).

---

## 📝 Notes
- Debug logs are controlled by Config.Debug in config.lua.
- This project is provided “as is”. Clean up and update as needed.

---



====================================================================

# 🇧🇷 Mesa de Drogas (vRP) para FiveM
Status: 🧊 Arquivado (sem manutenção)

Sistema simples de mesa de drogas para FiveM, baseado em vRP.
Este repositório está arquivado, então pode ter padrões antigos e incompatibilidades.

---

## ⚠️ Status do Projeto (Importante)
- Arquivado: este projeto não está mais em andamento e pode estar desatualizado.
- Use por sua conta e risco: verifique compatibilidade com sua versão do FiveM e do vRP antes de usar.

---

## 🚀 Instalação Rápida
1. Coloque a pasta do recurso dentro da pasta `resources` da sua gamemode.
2. Adicione no `server.cfg`:
   ensure script-para-fiveM-mesa-de-drogas
3. Requisito: vRP (dependência declarada em fxmanifest.lua).

---

## 🧩 Arquivos Principais
- Cliente
  - client.lua
    Funções importantes: CriarMesa, mesaDroga.ObjectControlling

- Servidor
  - server.lua
    Funções importantes: registrarMesa, agendarProximoSpawn

- Configuração
  - config.lua
    Valores principais: Config.Drogas, tempos e modelos

- Manifesto
  - fxmanifest.lua

- UI
  - html/index.html
  - html/script.js
  - html/style.css

---

## 🧪 Uso Básico
- Configure em config.lua conforme necessário.
- Suba o recurso no servidor e reinicie o recurso.
- Use o item `mesa_droga` para criar a mesa (integração com inventário vRP é esperada).

---

## 📝 Notas
- Logs de debug são controlados por Config.Debug em config.lua.
- Arquivo fornecido “como está”. Atualize/limpe conforme necessidade.


