#!/bin/bash
# smart_eye 一键测试脚本
# 用法: ./scripts/test.sh

set -e

echo "🧪 smart_eye 测试启动..."
echo ""

# 检查是否在项目根目录
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ 错误: 请在项目根目录运行此脚本"
    exit 1
fi

# 1. 代码分析
echo "🔍 步骤 1/4: 运行静态分析..."
flutter analyze
if [ $? -eq 0 ]; then
    echo "✅ 静态分析通过"
else
    echo "❌ 静态分析失败"
    exit 1
fi
echo ""

# 2. 代码格式化检查
echo "🎨 步骤 2/4: 检查代码格式..."
dart format --output=none --set-exit-if-changed lib/ test/
if [ $? -eq 0 ]; then
    echo "✅ 代码格式检查通过"
else
    echo "❌ 代码格式检查失败，请运行: dart format lib/ test/"
    exit 1
fi
echo ""

# 3. 单元测试
echo "🧪 步骤 3/4: 运行单元测试..."
flutter test test/unit/
if [ $? -eq 0 ]; then
    echo "✅ 单元测试通过"
else
    echo "❌ 单元测试失败"
    exit 1
fi
echo ""

# 4. 集成测试（如果有）
if [ -d "test/integration" ] && [ "$(ls -A test/integration/)" ]; then
    echo "🔗 步骤 4/4: 运行集成测试..."
    flutter test test/integration/
    if [ $? -eq 0 ]; then
        echo "✅ 集成测试通过"
    else
        echo "❌ 集成测试失败"
        exit 1
    fi
else
    echo "⏭️ 步骤 4/4: 暂无集成测试，跳过"
fi
echo ""

echo "🎉 全部测试通过！"
echo ""
echo "提交前自检清单:"
echo "  ✅ flutter analyze 零警告"
echo "  ✅ dart format 无变更"
echo "  ✅ flutter test 全绿"
echo "  ✅ 新增代码有先失败过的测试"
echo "  ✅ 所有交互元素有 Semantics"
echo "  ✅ 所有用户操作有语音反馈"
