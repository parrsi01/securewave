.PHONY: flutter-get flutter-run flutter-build-linux linux-package linux-runtime-install backend-run

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

backend-run:
	bash scripts/run_backend.sh
