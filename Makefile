.PHONY: app run install test selftest snapshots icon clean

app:            ## Build build/Sticky Things.app
	@scripts/build-app.sh

run: app        ## Build and launch from ./build
	@pkill -x StickyThings 2>/dev/null || true
	@sleep 0.3
	@open "build/Sticky Things.app"

install:        ## Build, copy to /Applications and launch
	@scripts/build-app.sh --install

test:           ## Unit tests: core, design system (contrast + lint), app logic
	@swift test

selftest:       ## Drive the real panel through accessibility (throwaway library)
	@swift build && .build/debug/StickyThings --selftest

snapshots:      ## Render every screen to build/snapshots
	@swift build && .build/debug/StickyThings --snapshot build/snapshots

icon:           ## Redraw the app icon
	@swift scripts/make-icon.swift Resources/AppIcon.icns

clean:
	@rm -rf .build build
