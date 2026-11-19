SHELL := /bin/bash
.DEFAULT_GOAL := test-unit-sdk
JOBS ?= 4
X := mise exec
# Git hooks must not leak their checkout-specific variables into SwiftPM subprocesses.
unexport $(shell git rev-parse --local-env-vars 2>/dev/null)
SWIFTFORMAT := $(X) swiftformat@0.64.7 -- swiftformat
SWIFTLINT := $(X) swiftlint@0.65.1 -- swiftlint lint --strict --quiet
RUFF := $(X) ruff@0.17.5 -- ruff
OXFMT := $(X) node@26.13.1 -- npx --yes oxfmt@0.78.0 --threads=$(JOBS)
.PHONY: fix lint-sdk lint-workflows test-unit-sdk test-integration-sdk test-ui-sdk lint all-tests

# Format only the staged paths passed by the pre-commit hook.
FILES ?= $(shell git diff --cached --name-only --diff-filter=ACMR)
fix:
	$(if $(filter %.swift,$(FILES)),$(SWIFTFORMAT) $(filter %.swift,$(FILES)),@:)
	$(if $(filter %.py,$(FILES)),$(RUFF) check --fix $(filter %.py,$(FILES)),@:)
	$(if $(filter %.py,$(FILES)),$(RUFF) format $(filter %.py,$(FILES)),@:)
	$(if $(filter %.ts %.js %.mjs %.json,$(FILES)),$(OXFMT) $(filter %.ts %.js %.mjs %.json,$(FILES)),@:)

lint-workflows:
	$(X) actionlint@1.7.12 -- actionlint

lint-sdk:
	$(SWIFTFORMAT) Sources Tests Demo Package.swift --lint
	$(SWIFTLINT)
	cd server && $(X) node@26.13.1 -- npx --no-install oxfmt --check .
	cd server && $(X) node@26.13.1 -- npx --no-install oxlint --deny-warnings
	cd server && $(X) node@26.13.1 -- npm run typecheck
	cd server && $(X) node@26.13.1 -- npm run build
	swift build -j $(JOBS)
	base=$$(git tag -l 'v[0-9]*' --sort=-v:refname | head -1); test -n "$$base"; swift package -j $(JOBS) diagnose-api-breaking-changes "$$base"

test-unit-sdk:
	swift test -j $(JOBS) --filter "AgentChatKitTests|AgentChatLiveUnitTests"
	cd server && $(X) node@26.13.1 -- npm run test:unit

test-integration-sdk:
	swift test -j $(JOBS) --filter "AgentChatKitIntegrationTests|AgentChatLiveIntegrationTests"
	cd server && $(X) node@26.13.1 -- npm run test:integration

PLATFORM ?= ios
SIMULATOR ?=
UI_SCHEME = $(if $(filter mac,$(PLATFORM)),AgentChatDemo-macOS,AgentChatDemo-iOS)
UI_PLAN = $(if $(filter mac,$(PLATFORM)),SDK-macOS,SDK-iOS)
ifeq ($(PLATFORM),mac)
UI_DESTINATION = platform=macOS
else
UI_DESTINATION = platform=iOS Simulator,id=$(SIMULATOR)
endif
test-ui-sdk:
ifeq ($(PLATFORM),mac)
	swift test -j $(JOBS) --filter AgentChatRenderingTests
endif
	xcodebuild test -project Demo/AgentChatDemo.xcodeproj -scheme $(UI_SCHEME) -testPlan $(UI_PLAN) \
		-destination '$(UI_DESTINATION)' -derivedDataPath Demo/build/DerivedData \
		-resultBundlePath Demo/build/ui-$(PLATFORM).xcresult -parallel-testing-enabled NO \
		-retry-tests-on-failure -test-iterations 2 -jobs $(JOBS)

lint: lint-sdk lint-workflows
all-tests: test-unit-sdk test-integration-sdk test-ui-sdk
