SHELL := /bin/bash
.DEFAULT_GOAL := test-unit-sdk
JOBS ?= 4
X := mise exec
SWIFTFORMAT := $(X) swiftformat@0.64.7 -- swiftformat
SWIFTLINT := $(X) swiftlint@0.65.1 -- swiftlint lint --strict --quiet
.PHONY: lint-sdk lint-workflows test-unit-sdk test-integration-sdk test-ui-sdk lint all-tests

lint-workflows:
	$(X) actionlint@1.7.12 -- actionlint

lint-sdk:
	$(SWIFTFORMAT) Sources Tests Demo Package.swift --lint
	$(SWIFTLINT)
	cd server && $(X) -- npx --no-install oxfmt --check .
	cd server && $(X) -- npx --no-install oxlint --deny-warnings
	cd server && $(X) -- npm run typecheck
	cd server && $(X) -- npm run build
	swift build -j $(JOBS)
	base=$$(git tag -l 'v[0-9]*' --sort=-v:refname | head -1); test -n "$$base"; swift package -j $(JOBS) diagnose-api-breaking-changes "$$base"

test-unit-sdk:
	swift test -j $(JOBS) --filter "AgentChatKitTests|AgentChatLiveUnitTests"
	cd server && $(X) -- npm run test:unit

test-integration-sdk:
	swift test -j $(JOBS) --filter "AgentChatKitIntegrationTests|AgentChatLiveIntegrationTests"
	cd server && $(X) -- npm run test:integration

PLATFORM ?= ios
SIMULATOR ?=
UI_SCHEME = $(if $(filter mac,$(PLATFORM)),AgentChatDemo-macOS,AgentChatDemo-iOS)
UI_PLAN = $(if $(filter mac,$(PLATFORM)),SDK-macOS,SDK-iOS)
UI_DESTINATION = $(if $(filter mac,$(PLATFORM)),platform=macOS,id=$(SIMULATOR))
test-ui-sdk:
	xcodebuild test -project Demo/AgentChatDemo.xcodeproj -scheme $(UI_SCHEME) -testPlan $(UI_PLAN) 		-destination '$(UI_DESTINATION)' -derivedDataPath Demo/build/DerivedData 		-resultBundlePath Demo/build/ui-$(PLATFORM).xcresult -parallel-testing-enabled NO 		-retry-tests-on-failure -test-iterations 2 -jobs $(JOBS)

lint: lint-sdk lint-workflows
all-tests: test-unit-sdk test-integration-sdk test-ui-sdk
