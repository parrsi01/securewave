.PHONY: flutter-get flutter-run flutter-build-linux linux-package linux-runtime-install linux-runtime-check linux-live-auth-init linux-live-debug

APP_DIR := securewave_app

flutter-get:
	FORCE_FLUTTER_ENV=true bash scripts/prepare_flutter_env.sh
	cd $(APP_DIR) && flutter pub get

flutter-run:
	bash scripts/run_flutter_linux.sh

flutter-build-linux:
	FORCE_FLUTTER_ENV=true bash scripts/prepare_flutter_env.sh
	cd $(APP_DIR) && flutter pub get && flutter build linux --release

linux-package:
	FORCE_FLUTTER_ENV=true bash scripts/prepare_flutter_env.sh
	cd $(APP_DIR) && bash scripts/build_deb.sh

linux-runtime-install:
	bash scripts/setup_linux_runtime.sh

linux-runtime-check:
	python3 scripts/linux_vpn_runtime_verifier.py --json

linux-live-auth-init:
	python3 scripts/init_linux_live_auth.py

linux-live-debug:
	bash scripts/live_linux_no_prompt_proof.sh
