# ──────────────────────────────────────────────────────────
# GameBox — Makefile de Orquestación
# Simplifica el ciclo de vida de tu consola auto-contenedorizada
# ──────────────────────────────────────────────────────────

.PHONY: build up down restart logs status shell host-setup clean help

help:
	@echo "=========================================================="
	@echo "  GameBox — Comandos de Orquestación"
	@echo "=========================================================="
	@echo "  make build       - Construye la imagen Docker"
	@echo "  make up          - Levanta el contenedor en segundo plano"
	@echo "  make down        - Detiene y remueve el contenedor"
	@echo "  make restart     - Reinicia el contenedor"
	@echo "  make logs        - Muestra los logs en tiempo real"
	@echo "  make status      - Comprueba el estado del contenedor"
	@echo "  make shell       - Abre un shell bash dentro del contenedor"
	@echo "  make host-setup  - Configura reglas udev para uinput en el host"
	@echo "  make clean       - Limpia recursos huérfanos de Docker"
	@echo "=========================================================="

build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

status:
	@docker ps -f name=gamebox
	@echo ""
	@echo "Sunshine Web UI disponible en: http://localhost:47990"

shell:
	docker exec -it gamebox bash

host-setup:
	@echo "[INFO] Configurando reglas udev para /dev/uinput en el host..."
	@echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' | sudo tee /etc/udev/rules.d/99-gamebox-uinput.rules
	@sudo modprobe uinput
	@sudo udevadm control --reload-rules && sudo udevadm trigger
	@echo "[OK] Reglas udev instaladas. Asegúrate de que tu usuario de host esté en el grupo 'input'."
	@echo "     # sudo usermod -aG input \$$USER"

clean:
	docker compose down --rmi local --volumes --remove-orphans
	docker image prune -f
