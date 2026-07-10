#!/bin/bash
# smart_eye 一键发布脚本
# 用法: ./scripts/release.sh v0.6.2
# 流程:
#   1. 运行 test.sh 确保所有测试通过
#   2. 构建 release APK
#   3. 推送 main + tag 到 github / origin (Gitee)
#   4. 可选: 推送到手机验证 (需设置 RELEASE_INSTALL=1)

set -e

# ====== 参数检查 ======
if [ $# -ne 1 ]; then
    echo "❌ 用法: $0 <version-tag>"
    echo "   示例: $0 v0.6.2"
    exit 1
fi

VERSION_TAG="$1"

# 校验 tag 格式 (vX.Y.Z)
if ! [[ "$VERSION_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "❌ 错误: tag 格式必须为 vX.Y.Z (例如 v0.6.2)"
    exit 1
fi

# ====== v1.0 发布冻结门禁 ======
# 在未完成 v1.0 readiness checklist 前，禁止发布 major >= 1 的版本。
# 如需强制发布 v1.0，必须显式设置 ALLOW_V1_RELEASE=1。
TAG_MAJOR=$(echo "$VERSION_TAG" | sed -E 's/^v([0-9]+).*/\1/')
PUBSPEC_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | tr -d ' ')
PUBSPEC_MAJOR=$(echo "$PUBSPEC_VERSION" | cut -d. -f1)

if [ "$TAG_MAJOR" -ge 1 ] && [ "${ALLOW_V1_RELEASE:-0}" != "1" ]; then
    echo "❌ 错误: 当前禁止发布 v1.0 及以上版本"
    echo "   原因: VERSION.md 中的 v1.0 readiness checklist 尚未全部完成"
    echo "   如需强制发布，请设置: ALLOW_V1_RELEASE=1 $0 $VERSION_TAG"
    echo "   注意: 强制发布前必须人工确认 checklist 已全部通过"
    exit 1
fi

if [ "$PUBSPEC_MAJOR" -ge 1 ] && [ "${ALLOW_V1_RELEASE:-0}" != "1" ]; then
    echo "❌ 错误: pubspec.yaml 的 major 版本为 $PUBSPEC_MAJOR，已达到 v1.0 冻结线"
    echo "   在未完成 v1.0 readiness checklist 前，不允许将 major 版本提升到 1"
    exit 1
fi

# 校验 tag 与 pubspec.yaml 的 versionName 一致（Flutter 的 +build 不计入 tag）
PUBSPEC_VERSION_NAME=$(echo "$PUBSPEC_VERSION" | cut -d'+' -f1)
EXPECTED_TAG="v$PUBSPEC_VERSION_NAME"
if [ "$VERSION_TAG" != "$EXPECTED_TAG" ]; then
    echo "❌ 错误: tag '$VERSION_TAG' 与 pubspec.yaml versionName '$PUBSPEC_VERSION_NAME' 不一致"
    echo "   请同步 VERSION.md、CHANGELOG.md 和 pubspec.yaml 后再发布"
    exit 1
fi

# ====== 环境检查 ======
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ 错误: 请在项目根目录运行此脚本"
    exit 1
fi

# 检查 main 分支 (避免误发)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "❌ 错误: 当前在分支 '$CURRENT_BRANCH'，发布必须在 main 分支"
    echo "   请先合并 feature 分支到 main: git checkout main && git merge <feature>"
    exit 1
fi

# 检查工作目录是否干净
if [ -n "$(git status --short)" ]; then
    echo "❌ 错误: 工作目录不干净，请先 commit 或 stash"
    git status --short
    exit 1
fi

# 检查 tag 是否已存在
if git rev-parse "$VERSION_TAG" >/dev/null 2>&1; then
    echo "❌ 错误: tag '$VERSION_TAG' 已存在"
    exit 1
fi

# ====== 步骤 1: 运行测试 ======
echo ""
echo "🧪 步骤 1/6: 运行测试套件..."
./scripts/test.sh

# ====== 步骤 2: 构建 Release APK ======
echo ""
echo "🔨 步骤 2/6: 构建 Release APK..."
flutter build apk --release
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
echo "✅ APK 构建完成: $APK_PATH ($APK_SIZE)"

# ====== 步骤 3: 推送到双仓库 ======
echo ""
echo "🚀 步骤 3/6: 推送到 GitHub + Gitee..."

# 同步 main 到两个 remote
echo "   推 main → github..."
git push github main
echo "   推 main → gitee..."
git push origin main

# 打 tag 并推送
echo "   打 tag: $VERSION_TAG"
git tag "$VERSION_TAG"
echo "   推 tag → github..."
git push github "$VERSION_TAG"
echo "   推 tag → gitee..."
git push origin "$VERSION_TAG"

echo "✅ 标签已推送到 GitHub + Gitee"
echo "   GitHub: https://github.com/pomelo56/smart_eye/releases/tag/$VERSION_TAG"
echo "   Gitee:  https://gitee.com/free-style_2_0/smart_eye/releases/tag/$VERSION_TAG"

# ====== 步骤 4: 可选 - 安装到手机 ======
echo ""
if [ "${RELEASE_INSTALL:-0}" = "1" ]; then
    echo "📱 步骤 4/4: 推送到手机验证..."
    DEVICE=$(adb devices | awk 'NR==2 {print $1}')
    if [ -z "$DEVICE" ]; then
        echo "❌ 未检测到 adb 设备，跳过安装"
    else
        echo "   目标设备: $DEVICE"
        adb -s "$DEVICE" install -r "$APK_PATH"
        echo "✅ 已安装到 $DEVICE"
    fi
else
    echo "⏭️ 步骤 4/6: 跳过手机安装 (设置 RELEASE_INSTALL=1 启用)"
fi

# ====== 步骤 5: 可选 - 发布到 Gitee release ======
echo ""
if [ -n "${GITEE_TOKEN:-}" ]; then
    if command -v ./scripts/release-gitee.sh >/dev/null 2>&1; then
        echo "📦 发布到 Gitee release (找到 GITEE_TOKEN)..."
        ./scripts/release-gitee.sh "$VERSION_TAG" "$APK_PATH"
    fi
else
    echo "⏭️ 跳过 Gitee release 发布 (未设置 GITEE_TOKEN)"
    echo "   设置方法: export GITEE_TOKEN=<你的令牌>"
    echo "   令牌生成: https://gitee.com/personal_access_tokens"
fi

# ====== 步骤 6: 可选 - 发布到 GitHub release ======
echo ""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "📦 发布到 GitHub release (gh CLI 已登录)..."
    ./scripts/release-github.sh "$VERSION_TAG" "$APK_PATH"
else
    echo "⏭️ 跳过 GitHub release 发布 (gh CLI 未登录或未安装)"
    echo "   登录方法: gh auth login --web  # 弹浏览器"
    echo "   或:       gh auth login --with-token < token.txt"
    echo "   验证:     gh auth status"
    echo "   安装:     brew install gh"
fi

# ====== 收尾 ======
echo ""
echo "🎉 发布完成!"
echo ""
echo "📋 发布摘要:"
echo "  标签:    $VERSION_TAG"
echo "  APK:     $APK_PATH ($APK_SIZE)"
echo "  GitHub:  https://github.com/pomelo56/smart_eye/releases/tag/$VERSION_TAG"
echo "  Gitee:   https://gitee.com/free-style_2_0/smart_eye/releases/tag/$VERSION_TAG"
