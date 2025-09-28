.PHONY: build seal run stop clean status diag seal-verify rebuild debug logs ps help

include .env
export

IMAGE_NAME        ?= access2work
CONTAINER_NAME    ?= access2work_container
SEAL_MODE         ?= normal     # normal | force | dryrun
RUN_MODE          ?= detached   # detached | debug
KEEP_ALIVE        ?= true       # true | false

VOLUMES = \
	-v $(PWD)/vpn_configs:/vpn/vpn_configs \
	-v $(PWD)/vpn_profiles:/vpn/vpn_profiles \
	-v $(PWD)/secrets:/vpn/secrets

build:
	docker build -t $(IMAGE_NAME) .

seal:
	@echo "🔐 Шифрование секретов — режим: $(SEAL_MODE)"
	docker run --rm --env-file .env \
		-e SEAL_MODE=$(SEAL_MODE) \
		$(VOLUMES) $(IMAGE_NAME) python3 /vpn/seal.py

run:
	@echo "🚀 Запуск контейнера — режим: $(RUN_MODE)"
	-docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	@if [ "$(RUN_MODE)" = "debug" ]; then \
		docker run -it --name $(CONTAINER_NAME) \
			--env-file .env --cap-add=NET_ADMIN --device /dev/net/tun \
			$(VOLUMES) $(IMAGE_NAME); \
	else \
		docker run -d --name $(CONTAINER_NAME) \
			--env-file .env --cap-add=NET_ADMIN --device /dev/net/tun \
			$(VOLUMES) $(IMAGE_NAME) $(if $(KEEP_ALIVE),sh -c "python3 /vpn/dial.py && tail -f /dev/null",python3 /vpn/dial.py); \
	fi

stop:
	@if docker ps -a --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		docker stop $(CONTAINER_NAME); \
	else \
		echo "❌ Контейнер $(CONTAINER_NAME) не существует"; \
	fi

clean:
	rm -f secrets/*.log secrets/*.gpg secrets/*.auth

status:
	@if ! docker ps --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "❌ Контейнер $(CONTAINER_NAME) не запущен"; \
	else \
		docker exec $(CONTAINER_NAME) sh -c "\
			echo '🌐 Внутренний IP:' && curl -s https://api.ipify.org || echo '❌ IP недоступен'; \
			echo '\n🧭 Интерфейсы:' && ip -brief address || echo '❌ ip не найден'; \
			echo '\n📡 Маршруты:' && ip route show || echo '❌ ip route не найден'; \
			echo '\n🔒 VPN-интерфейсы:' && ip link show | grep tun || echo '❌ tun не найден'"; \
	fi

diag:
	@if ! docker ps --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "❌ Контейнер $(CONTAINER_NAME) не запущен"; \
	else \
		docker exec $(CONTAINER_NAME) sh -c "\
			echo '🧪 VPN диагностика — $$(date)'; \
			echo '\n🌍 Внешний IP:' && curl -s https://ifconfig.me || echo '❌ curl не сработал'; \
			echo '\n📡 Интерфейсы:' && ip addr show || echo '❌ ip addr не сработал'; \
			echo '\n🧭 Маршруты:' && ip route show || echo '❌ ip route не сработал'; \
			echo '\n🔌 Интерфейс tun0:' && ip addr show dev tun0 || echo '❌ tun0 не найден'; \
			echo '\n📋 Процесс OpenVPN:' && ps -ef | grep openvpn | grep -v grep || echo '❌ openvpn не запущен'"; \
	fi

seal-verify: seal diag
	@echo "\n📄 vpn_connect.log:" && tail -n 20 secrets/vpn_connect.log || echo "❌ vpn_connect.log не найден"
	@echo "\n📄 vpn_seal.log:" && tail -n 20 secrets/vpn_seal.log || echo "❌ vpn_seal.log не найден"

rebuild: clean build run seal diag

debug: clean build run RUN_MODE=debug

logs:
	@if ! docker ps -a --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "❌ Контейнер $(CONTAINER_NAME) не существует"; \
	else \
		docker logs $(CONTAINER_NAME); \
	fi

ps:
	docker ps -a | grep $(CONTAINER_NAME) || echo "❌ Контейнер $(CONTAINER_NAME) не найден"

help:
	@echo "📦 Makefile цели:"
	@echo "  build         — Сборка Docker-образа"
	@echo "  seal          — Шифрование секретов (SEAL_MODE=normal|force|dryrun)"
	@echo "  run           — Запуск контейнера (RUN_MODE=detached|debug, KEEP_ALIVE=true|false)"
	@echo "  stop          — Остановка контейнера"
	@echo "  clean         — Очистка временных файлов (.auth, .log, .gpg)"
	@echo "  status        — Проверка IP, интерфейсов, маршрутов"
	@echo "  diag          — Расширенная диагностика VPN"
	@echo "  seal-verify   — Шифрование + диагностика + лог-фрагменты"
	@echo "  rebuild       — Полная пересборка и запуск"
	@echo "  debug         — Сборка и запуск в debug-режиме"
	@echo "  logs          — Вывод логов контейнера"
	@echo "  ps            — Список контейнеров"
	@echo "  help          — Эта справка"
