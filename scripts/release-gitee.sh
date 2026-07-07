#!/bin/bash
# Gitee Release 发布器
# 用法: ./scripts/release-gitee.sh <version-tag> <apk-path>
#   e.g. ./scripts/release-gitee.sh v0.6.2 build/app/outputs/flutter-apk/app-release.apk
#
# 必设环境变量:
#   GITEE_TOKEN - Gitee 私人令牌 (https://gitee.com/personal_access_tokens)
#                 需要 scope: projects, releases
# 可设环境变量:
#   GITEE_REPO  - 仓库路径 (默认 free-style_2_0/smart_eye)

set -e

# ====== 参数检查 ======
if [ $# -ne 2 ]; then
    echo "❌ 用法: $0 <version-tag> <apk-path>"
    exit 1
fi

VERSION_TAG="$1"
APK_PATH="$2"

if [ -z "${GITEE_TOKEN:-}" ]; then
    echo "❌ 错误: 未设置 GITEE_TOKEN"
    echo "   获取令牌: https://gitee.com/personal_access_tokens"
    echo "   需要 scope: projects, releases"
    exit 1
fi

if [ ! -f "$APK_PATH" ]; then
    echo "❌ 错误: APK 文件不存在: $APK_PATH"
    exit 1
fi

GITEE_REPO="${GITEE_REPO:-free-style_2_0/smart_eye}"
GITEE_API="https://gitee.com/api/v5"

# 从 CHANGELOG.md 提取本版本说明
extract_changelog() {
    local tag="$1"
    local changelog="CHANGELOG.md"
    if [ ! -f "$changelog" ]; then
        echo "Release $tag"
        return
    fi
    # 找 [tag] 段到下一个 [ 段之前的内容
    awk -v target="## [$tag]" '
        $0 ~ target { capture=1; next }
        capture && /^## \[/ { exit }
        capture { print }
    ' "$changelog" | head -c 4000
}

RELEASE_BODY=$(extract_changelog "$VERSION_TAG")
if [ -z "$RELEASE_BODY" ]; then
    RELEASE_BODY="详见 [CHANGELOG.md](https://gitee.com/${GITEE_REPO}/blob/${VERSION_TAG}/CHANGELOG.md)"
fi

APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
APK_NAME="smart_eye-${VERSION_TAG}.apk"

# ====== 1. 创建 release ======
echo ""
echo "📦 创建 Gitee release: $VERSION_TAG"

CREATE_BODY=$(jq -n \
    --arg tag_name "$VERSION_TAG" \
    --arg name "$VERSION_TAG" \
    --arg body "$RELEASE_BODY" \
    --arg target_commitish "main" \
    '{tag_name: $tag_name, name: $name, body: $body, target_commitish: $target_commitish, prerelease: false}')

CREATE_RESPONSE=$(curl -sS -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: token $GITEE_TOKEN" \
    -d "$CREATE_BODY" \
    "${GITEE_API}/repos/${GITEE_REPO}/releases")

# 检查是否创建成功 (返回 json 包含 id)
if ! echo "$CREATE_RESPONSE" | grep -q '"id"'; then
    if echo "$CREATE_RESPONSE" | grep -q '已经存在'; then
        echo "ℹ️  Release $VERSION_TAG 已存在，跳过创建"
    else
        echo "❌ 创建失败: $CREATE_RESPONSE"
        exit 1
    fi
else
    echo "✅ Release 创建成功"
fi

# ====== 2. 上传 APK 附件 ======
echo ""
echo "📎 上传 APK ($APK_SIZE)..."

UPLOAD_RESPONSE=$(curl -sS -X POST \
    -H "Authorization: token $GITEE_TOKEN" \
    -F "file=@${APK_PATH};filename=${APK_NAME}" \
    -F "label=${APK_NAME}" \
    "${GITEE_API}/repos/${GITEE_REPO}/releases/${VERSION_TAG}/assets")

if echo "$UPLOAD_RESPONSE" | grep -q '"browser_download_url"'; then
    DOWNLOAD_URL=$(echo "$UPLOAD_RESPONSE" | grep -oE '"browser_download_url":"[^"]+"' | head -1 | cut -d'"' -f4)
    echo "✅ APK 上传成功"
    echo "   下载: $DOWNLOAD_URL"
else
    echo "❌ 上传失败: $UPLOAD_RESPONSE"
    exit 1
fi

echo ""
echo "🎉 Gitee release 发布完成!"
echo "   https://gitee.com/${GITEE_REPO}/releases/tag/${VERSION_TAG}"
