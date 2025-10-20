.PHONY: build seal run stop clean status diag seal-verify rebuild debug logs ps help

include .env
export

IMAGE_NAME        ?= access2work
CONTAINER_NAME    ?= access2work_container
SEAL_MODE         ?= normal     # normal | force | dryrun

VOLUMES = \
	-v $(PWD)/vpn_configs:$(VPN_CONFIG_DIR) \
	-v $(PWD)/vpn_profiles:$(VPN_PROFILE_DIR) \
	-v $(PWD)/secrets:$(VPN_SECRET_DIR) \
	-v ~/.ssh:/root/ssh:ro

DB_PORT_FLAGS := $(shell jq -r '.[] | "-p \(.port):\(.port)"' scripts/db_targets.json | xargs)

build:
	docker build -t $(IMAGE_NAME) .

seal:
	@echo "🔐 Шифрование секретов — режим: $(SEAL_MODE)"
	@if ! docker image inspect $(IMAGE_NAME) >/dev/null 2>&1; then \
		echo "📦 Образ $(IMAGE_NAME) не найден — запускаем сборку..."; \
		$(MAKE) build; \
	fi
	docker run --rm --env-file .env \
		-e SEAL_MODE=$(SEAL_MODE) \
		$(VOLUMES) \
		$(IMAGE_NAME) python3 /vpn/seal.py

run:
	-docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	docker run -d --name $(CONTAINER_NAME) \
		--env-file .env \
		--cap-add=NET_ADMIN --device /dev/net/tun \
		$(VOLUMES) \
		-p $(GIT_PROXY_PORT):$(GIT_PROXY_PORT) \
		$(DB_PORT_FLAGS) \
		-p 9100:9100 \
		-p 80:80 \
		-p 443:443 \
		$(IMAGE_NAME)

wait:
	@echo "⏳ Ожидание готовности контейнера..."
	@timeout 90 bash -c 'until [ "$$(docker inspect -f {{.State.Health.Status}} $(CONTAINER_NAME))" = "healthy" ]; do sleep 2; done'
	@echo "✅ Контейнер $(CONTAINER_NAME) полностью готов"

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
			echo '\n🧭 Интерфейсы:' && ip -brief address || echo '❌ ip не найден'; \
			echo '\n📡 Маршруты:' && ip route show || echo '❌ ip route не найден'; \
			echo '\n🔒 VPN-интерфейсы:' && ip link show | grep tun || echo '❌ tun не найден'"; \
	fi

diag:
	@echo "🔍 Запуск диагностики контейнера..."
	@if ! docker ps --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "❌ Контейнер $(CONTAINER_NAME) не запущен"; \
	else \
		docker exec $(CONTAINER_NAME) bash /vpn/diag.sh; \
	fi

logs:
	@if ! docker ps -a --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "❌ Контейнер $(CONTAINER_NAME) не существует"; \
	else \
		docker logs $(CONTAINER_NAME); \
	fi

ps:
	docker ps -a | grep $(CONTAINER_NAME) || echo "❌ Контейнер $(CONTAINER_NAME) не найден"

rebuild: clean build seal run wait logs status

help:
	@echo "📦 Makefile цели:"
	@echo "  build         — Сборка Docker-образа"
	@echo "  seal          — Шифрование секретов (SEAL_MODE=normal|force|dryrun)"
	@echo "  run           — Запуск контейнера"
	@echo "  stop          — Остановка контейнера"
	@echo "  clean         — Очистка временных файлов (.auth, .log, .gpg)"
	@echo "  status        — Проверка IP, интерфейсов, маршрутов"
	@echo "  diag          — Расширенная диагностика VPN"
	@echo "  rebuild       — Полная пересборка и запуск"
	@echo "  logs          — Вывод логов контейнера"
	@echo "  ps            — Список контейнеров"
	@echo "  help          — Эта справка"
