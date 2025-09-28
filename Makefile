.PHONY: build seal run stop clean status diag seal-verify rebuild debug

include .env
export

IMAGE_NAME ?= access2work
CONTAINER_NAME ?= access2work_container
SEAL_MODE ?= normal     # normal | force | dryrun
RUN_MODE ?= detached    # detached | debug

build:
	docker build -t $(IMAGE_NAME) .

seal:
	@echo "🔐 Шифрование секретов — режим: $(SEAL_MODE)"
	docker run --rm --env-file .env \
		-e SEAL_MODE=$(SEAL_MODE) \
		-v $(PWD)/vpn_configs:/vpn/vpn_configs \
		-v $(PWD)/secrets:/vpn/secrets \
		$(IMAGE_NAME) python3 /vpn/seal.py

run:
	@echo "🚀 Запуск контейнера — режим: $(RUN_MODE)"
	-docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	@if [ "$(RUN_MODE)" = "debug" ]; then \
		docker run -it --name $(CONTAINER_NAME) \
			--env-file .env \
			--cap-add=NET_ADMIN --device /dev/net/tun \
			-v $(PWD)/vpn_configs:/vpn/vpn_configs \
			-v $(PWD)/vpn_profiles:/vpn/vpn_profiles \
			-v $(PWD)/secrets:/vpn/secrets \
			$(IMAGE_NAME); \
	else \
		docker run -d --name $(CONTAINER_NAME) \
			--env-file .env \
			--cap-add=NET_ADMIN --device /dev/net/tun \
			-v $(PWD)/vpn_configs:/vpn/vpn_configs \
			-v $(PWD)/vpn_profiles:/vpn/vpn_profiles \
			-v $(PWD)/secrets:/vpn/secrets \
			$(IMAGE_NAME); \
	fi

stop:
	docker stop $(CONTAINER_NAME) || true

clean:
	rm -f secrets/*.log secrets/*.gpg

status:
	docker exec $(CONTAINER_NAME) sh -c "\
		echo '🌐 Внутренний IP:' && curl -s https://api.ipify.org || echo '❌ IP недоступен'; \
		echo '\n🧭 Интерфейсы:' && ip -brief address || echo '❌ ip не найден'; \
		echo '\n📡 Маршруты:' && ip route show || echo '❌ ip route не найден'; \
		echo '\n🔒 VPN-интерфейсы:' && ip link show | grep tun || echo '❌ tun не найден'"

diag:
	@docker inspect -f '{{.State.Running}}' $(CONTAINER_NAME) 2>/dev/null | grep true >/dev/null || \
		{ echo "❌ Контейнер $(CONTAINER_NAME) не запущен"; exit 1; }
	docker exec $(CONTAINER_NAME) sh -c "\
		chmod +x /vpn/vpn-diag.sh && \
		sh /vpn/vpn-diag.sh && \
		echo '\n📄 vpn_diag.log:' && \
		cat /vpn/secrets/vpn_diag.log || echo '❌ Лог не найден'"

seal-verify:
	@echo "🔐 Шифрование + 🧪 Диагностика + 📄 Логи"
	make seal SEAL_MODE=$(SEAL_MODE)
	make diag
	@echo "\n📄 vpn_connect.log:"
	@tail -n 20 secrets/vpn_connect.log || echo "❌ vpn_connect.log не найден"
	@echo "\n📄 vpn_seal.log:"
	@tail -n 20 secrets/vpn_seal.log || echo "❌ vpn_seal.log не найден"

rebuild:
	@echo "🧹 Очистка → 🔨 Сборка → 🚀 Запуск → 🔐 Шифрование → 🔌 Подключение → 🧪 Диагностика"
	make clean
	make build
	make run RUN_MODE=$(RUN_MODE)
	make seal SEAL_MODE=$(SEAL_MODE)
	make dial
	make diag

debug:
	make clean
	make build
	make run RUN_MODE=debug

dial:
	docker exec $(CONTAINER_NAME) python3 /vpn/dial.py

