#!/bin/bash

# 默认构建目录为build，而不是.build
BUILD_DIR="build"

# 解析命令行参数
if [[ $1 == "-c" && $2 == "release" ]]; then
    echo "正在进行Release构建..."
    swift build -c release --build-path "$BUILD_DIR"
elif [[ $1 == "-c" && $2 == "debug" ]]; then
    echo "正在进行Debug构建..."
    swift build --build-path "$BUILD_DIR"
elif [[ $1 == "--clean" ]]; then
    echo "正在清理构建产物..."
    rm -rf "$BUILD_DIR"
    rm -rf *.app
    echo "清理完成！"
elif [[ $1 == "--help" || $1 == "-h" ]]; then
    echo "使用方法：$0 [选项]"
    echo "  -c release    进行Release构建"
    echo "  -c debug      进行Debug构建（默认）"
    echo "  --clean       清理构建产物"
    echo "  --help/-h     显示此帮助信息"
    echo ""
    echo "构建产物会生成在 $BUILD_DIR 目录中"
else
    echo "正在进行Debug构建..."
    swift build --build-path "$BUILD_DIR"
fi
