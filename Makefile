.PHONY: build seal run stop clean status diag seal-verify rebuild debug dial

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
	rm -f secrets/*.log secrets/*.gpg secrets/*.auth

status:
	docker exec $(CONTAINER_NAME) sh -c "\
		echo '🌐 Внутренний IP:' && curl -s https://api.ipify.org || echo '❌ IP недоступен'; \
		echo '\n🧭 Интерфейсы:' && ip -brief address || echo '❌ ip не найден'; \
		echo '\n📡 Маршруты:' && ip route show || echo '❌ ip route не найден'; \
		echo '\n🔒 VPN-интерфейсы:' && ip link show | grep tun || echo '❌ tun не найден'"

diag:
	docker exec $(CONTAINER_NAME) sh -c "\
		echo '🧪 VPN диагностика — $$(date)'; \
		echo '\n🌍 Внешний IP:' && curl -s https://ifconfig.me || echo '❌ curl не сработал'; \
		echo '\n📡 Интерфейсы:' && ip addr show || echo '❌ ip addr не сработал'; \
		echo '\n🧭 Маршруты:' && ip route show || echo '❌ ip route не сработал'; \
		echo '\n🔌 Интерфейс tun0:' && ip addr show dev tun0 || echo '❌ tun0 не найден'; \
		echo '\n📋 Процесс OpenVPN:' && ps -ef | grep openvpn | grep -v grep || echo '❌ openvpn не запущен'"

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
