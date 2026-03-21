.PHONY: build release clean

APP_NAME = JustaUsageBar
SCHEME = JustaUsageBar
BUILD_DIR = build
RELEASE_DIR = $(BUILD_DIR)/Release
ARCHIVE_PATH = $(BUILD_DIR)/$(APP_NAME).xcarchive
APP_PATH = $(RELEASE_DIR)/$(APP_NAME).app
ZIP_PATH = $(BUILD_DIR)/$(APP_NAME).zip

# Build debug
build:
	xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Debug \
		build

# Build release and create zip for distribution
release:
	@mkdir -p $(RELEASE_DIR)
	xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR)/DerivedData \
		build
	@cp -R $(BUILD_DIR)/DerivedData/Build/Products/Release/$(APP_NAME).app $(RELEASE_DIR)/
	@cd $(RELEASE_DIR) && zip -r ../../$(ZIP_PATH) $(APP_NAME).app
	@echo ""
	@echo "Release built: $(ZIP_PATH)"
	@echo "SHA256: $$(shasum -a 256 $(ZIP_PATH) | cut -d' ' -f1)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Create a GitHub release with tag v<version>"
	@echo "  2. Upload $(ZIP_PATH) to the release"
	@echo "  3. Update Casks/justausagebar.rb with the SHA256 above"

clean:
	rm -rf $(BUILD_DIR)
	xcodebuild -project $(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		clean
