APP_NAME = ClaudeBar
DIST = dist
APP = $(DIST)/$(APP_NAME).app
BINARY = .build/release/$(APP_NAME)

.PHONY: build bundle run install preview clean

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BINARY) $(APP)/Contents/MacOS/$(APP_NAME)
	cp Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign - $(APP)
	@echo "Built $(APP)"

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
