.PHONY: app run install test icon clean

app:            ## Build build/Sticky Things.app
	@scripts/build-app.sh

run: app        ## Build and launch from ./build
	@pkill -x StickyThings 2>/dev/null || true
	@sleep 0.3
	@open "build/Sticky Things.app"

install:        ## Build, copy to /Applications and launch
	@scripts/build-app.sh --install

test:           ## Run unit tests
	@swift test

icon:           ## Redraw the app icon
	@swift scripts/make-icon.swift Resources/AppIcon.icns

clean:
	@rm -rf .build build
