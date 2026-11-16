.PHONY: app run install test selftest layout snapshots icon ios-project ios-build ios-open clean

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

layout:         ## Open the real panel in every state, check the grid, write captures to build/layout
	@swift build && .build/debug/StickyThings --layout build/layout

snapshots:      ## Render every screen to build/snapshots
	@swift build && .build/debug/StickyThings --snapshot build/snapshots

icon:           ## Redraw the app icon
	@swift scripts/make-icon.swift apps/macos/Resources/AppIcon.icns

ios-project:    ## Regenerate the iOS Xcode project (needs xcodegen)
	@cd apps/ios && xcodegen generate

ios-build: ios-project ## Build the iOS app and its extensions for the simulator
	@xcodebuild -project apps/ios/StickyThings.xcodeproj -scheme StickyThings \
		-sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
		-derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build

ios-open:       ## Open the iOS project in Xcode
	@open apps/ios/StickyThings.xcodeproj

clean:
	@rm -rf .build build
