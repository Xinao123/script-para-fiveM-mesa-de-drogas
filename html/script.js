let itemSelecionado = null;
let quantidadeMaxima = 0;

// Toast helper
function mostrarToast(mensagem, cor = "red") {
    const toastContainer = document.getElementById("toast-container");
    if (!toastContainer) return;
    const toast = document.createElement("div");
    toast.className = `toast ${cor}`;
    toast.textContent = mensagem;
    toastContainer.appendChild(toast);
    setTimeout(() => toast.remove(), 3000);
}
function toastErro(msg) { mostrarToast(msg, "red"); }
function toastSucesso(msg) { mostrarToast(msg, "green"); }

// Evento de mensagem da NUI
window.addEventListener("message", function(event) {
    const data = event.data;
    switch (data.action) {
        case "show":
            document.body.style.display = "block";
            updatePlayerInventory(data.player || {});
            updateMesaSlots(data.mesa || {});
            break;
        case "hide":
            document.body.style.display = "none";
            break;
    }
});

// Fechar painel
document.getElementById("fecharMesa").addEventListener("click", function () {
    fetch(`https://${GetParentResourceName()}/fecharMesa`, {
        method: "POST"
    });
});

// Confirmar quantidade e enviar droga
document.getElementById("confirmarQuantidade").addEventListener("click", function () {
    const quantidadeInput = document.getElementById("modal-quantidade").value;
    let quantidade = parseInt(quantidadeInput);

    if ((quantidadeInput === "" || isNaN(quantidade)) && quantidadeMaxima > 0) {
        quantidade = quantidadeMaxima;
    }

    if (
        typeof itemSelecionado === "string" &&
        itemSelecionado.trim() !== "" &&
        Number.isInteger(quantidade) &&
        quantidade > 0 &&
        quantidade <= quantidadeMaxima
    ) {
        fetch(`https://${GetParentResourceName()}/adicionarDroga`, {
            method: "POST",
            body: JSON.stringify({ item: itemSelecionado, quantidade }),
            headers: { "Content-Type": "application/json" }
        });
        toastSucesso(`Enviado ${quantidade}× ${itemSelecionado}`);
        fecharModal();
    } else {
        toastErro("Quantidade ou item inválido.");
    }
});

// Cancelar modal
document.getElementById("cancelarQuantidade").addEventListener("click", fecharModal);

// Modal de quantidade
function abrirModal(item, max) {
    if (!item || typeof item !== "string" || max <= 0) return;
    itemSelecionado = item;
    quantidadeMaxima = max;
    document.getElementById("modal-label").innerText = `Quantas unidades de ${item} você quer enviar? Confirme em branco para enviar todas. (Disponível: ${max})`;
    document.getElementById("modal-quantidade").value = "";
    document.getElementById("quantidade-modal").style.display = "flex";
}

function fecharModal() {
    document.getElementById("quantidade-modal").style.display = "none";
}

// Criação de slots visuais (player e mesa)
function createSlotElement(item, qtd, isMesa) {
    if (!item || typeof qtd !== "number" || qtd <= 0) return;
    const slot = document.createElement("div");
    slot.className = "slot";
    const img = document.createElement("img");
    img.src = `img/${item}.png`;
    img.alt = item;
    const qtyOverlay = document.createElement("div");
    qtyOverlay.className = "quantity-overlay";
    qtyOverlay.textContent = qtd;
    slot.appendChild(img);
    slot.appendChild(qtyOverlay);

    if (isMesa) {
        slot.addEventListener("dblclick", function () {
            fetch(`https://${GetParentResourceName()}/retirarDroga`, {
                method: "POST",
                body: JSON.stringify({ item }),
                headers: { "Content-Type": "application/json" }
            });
            toastSucesso(`Removido 1× ${item}`);
        });
    } else {
        slot.addEventListener("click", function () {
            abrirModal(item, qtd);
        });
    }
    return slot;
}

// Atualizar inventário do jogador
function updatePlayerInventory(playerInventory) {
    const container = document.getElementById("player-inventory");
    container.innerHTML = "";
    if (!playerInventory || typeof playerInventory !== "object") return;
    for (const [item, qtd] of Object.entries(playerInventory)) {
        const slot = createSlotElement(item, qtd, false);
        if (slot) container.appendChild(slot);
    }
}

// Atualizar slots da mesa
function updateMesaSlots(mesaInventory) {
    const container = document.getElementById("mesa-inventory");
    container.innerHTML = "";
    const keys = Object.keys(mesaInventory || {});
    for (let i = 0; i < 8; i++) {
        const item = keys[i];
        if (item) {
            const slot = createSlotElement(item, mesaInventory[item], true);
            if (slot) container.appendChild(slot);
        } else {
            const emptySlot = document.createElement("div");
            emptySlot.className = "slot empty";
            container.appendChild(emptySlot);
        }
    }
}
