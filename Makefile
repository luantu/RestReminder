# 默认构建目录为build，而不是.build
BUILD_DIR = build

.PHONY: build debug release clean

# 默认目标：debug构建
build: debug

# Debug构建
debug:
	swift build --build-path $(BUILD_DIR)

# Release构建
release:
	swift build -c release --build-path $(BUILD_DIR)

# 清理构建产物
clean:
	rm -rf $(BUILD_DIR)
	rm -rf *.app
