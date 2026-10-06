.PHONY: flutter-get flutter-run flutter-build-linux linux-package linux-runtime-install backend-run test-backend test-flutter test-native check docs

APP_DIR := securewave_app
PYTHON ?= python3

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

test-backend:
	TESTING=true ENVIRONMENT=testing DATABASE_URL=sqlite:///:memory: $(PYTHON) -m pytest -q --confcutdir=tests tests

test-flutter:
	cd $(APP_DIR) && flutter pub get && flutter analyze --no-pub && flutter test --no-pub

test-native:
	$(PYTHON) scripts/run_native_tests.py

check:
	$(PYTHON) scripts/check_repository.py
	git diff --check

docs:
	$(PYTHON) scripts/build_research_pdf.py
