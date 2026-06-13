APP_NAME = ClaudeBar
DIST = dist
APP = $(DIST)/$(APP_NAME).app
BINARY = .build/release/$(APP_NAME)

# Code-signing identity. Defaults to ad-hoc ("-"). Signing with a stable
# identity (an Apple Development cert or a self-signed one) keeps the app's
# code signature constant across rebuilds, so the macOS keychain "Always Allow"
# grant for the Claude Code token persists instead of re-prompting every build.
# Override locally without touching the repo: create local.mk with e.g.
#   CODESIGN_IDENTITY = <40-char identity hash from `security find-identity -p codesigning -v`>
-include local.mk
CODESIGN_IDENTITY ?= -

.PHONY: build bundle run install preview clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(CODESIGN_IDENTITY)" $(APP)
	@echo "Built $(APP) (signed: $(CODESIGN_IDENTITY))"

run: bundle
	open $(APP)

install: bundle
	mkdir -p $(HOME)/Applications
	rm -rf $(HOME)/Applications/$(APP_NAME).app
	cp -R $(APP) $(HOME)/Applications/
	@echo "Installed to ~/Applications/$(APP_NAME).app"

preview:
	swift build
	.build/debug/$(APP_NAME) --preview /tmp/claudebar-preview.png

clean:
	rm -rf .build $(DIST)
