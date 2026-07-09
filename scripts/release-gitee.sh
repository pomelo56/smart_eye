#!/bin/bash
# Gitee Release 发布器
# 用法: ./scripts/release-gitee.sh <version-tag> <apk-path>
#
# 必设环境变量:
#   GITEE_TOKEN - Gitee 私人令牌 (https://gitee.com/personal_access_tokens)
#                 需要 scope: projects, releases
# 可设环境变量:
#   GITEE_REPO  - 仓库路径 (默认 free-style_2_0/smart_eye)

set -e

if [ $# -ne 2 ]; then
    echo "❌ 用法: $0 <version-tag> <apk-path>"
    exit 1
fi

VERSION_TAG="$1"
APK_PATH="$2"

if [ -z "${GITEE_TOKEN:-}" ]; then
    echo "❌ 错误: 未设置 GITEE_TOKEN"
    echo "   获取令牌: https://gitee.com/personal_access_tokens"
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
    # CHANGELOG 标题格式是 `## [0.7.2]`（无 v 前缀），入参是 v0.7.2，
    # 所以先剥掉 v 前缀再做模式匹配。
    local bare="${tag#v}"
    awk -v target="## [$bare]" '
        $0 ~ target { capture=1; next }
        capture && /^## \[/ { exit }
        capture { print }
    ' "$changelog" | head -c 4000
}

RELEASE_BODY=$(extract_changelog "$VERSION_TAG")
# 如果设置了 GITEE_NOTES_FILE，直接从文件读 release body（优先级最高，
# 便于传带换行/emoji/引号的中文 markdown note）
if [ -n "${GITEE_NOTES_FILE:-}" ] && [ -f "$GITEE_NOTES_FILE" ]; then
    RELEASE_BODY=$(cat "$GITEE_NOTES_FILE")
elif [ -z "$RELEASE_BODY" ]; then
    RELEASE_BODY="详见 [CHANGELOG.md](https://gitee.com/${GITEE_REPO}/blob/${VERSION_TAG}/CHANGELOG.md)"
fi

APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
APK_NAME="smart_eye-${VERSION_TAG}.apk"

# ====== 1. 查 release ID (按 tag 找) ======
echo ""
echo "🔍 查找 release: $VERSION_TAG"

LOOKUP_RESPONSE=$(curl -sS \
    -H "Authorization: token $GITEE_TOKEN" \
    "${GITEE_API}/repos/${GITEE_REPO}/releases/tags/${VERSION_TAG}")

# 如果返回了 id，说明 release 已存在，直接用
if echo "$LOOKUP_RESPONSE" | grep -q '"id"'; then
    RELEASE_ID=$(echo "$LOOKUP_RESPONSE" | grep -oE '"id":[0-9]+' | head -1 | cut -d: -f2)
    echo "✅ Release 已存在 (id=$RELEASE_ID)"
else
    # 创建新 release
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

    if ! echo "$CREATE_RESPONSE" | grep -q '"id"'; then
        echo "❌ 创建失败: $CREATE_RESPONSE"
        exit 1
    fi

    RELEASE_ID=$(echo "$CREATE_RESPONSE" | grep -oE '"id":[0-9]+' | head -1 | cut -d: -f2)
    echo "✅ Release 创建成功 (id=$RELEASE_ID)"
fi

# ====== 2. 上传 APK 附件 (必须用 release_id) ======
echo ""
echo "📎 上传 APK ($APK_SIZE) 到 release_id=$RELEASE_ID..."

UPLOAD_RESPONSE=$(curl -sS -X POST \
    -H "Authorization: token $GITEE_TOKEN" \
    -F "file=@${APK_PATH};filename=${APK_NAME}" \
    "${GITEE_API}/repos/${GITEE_REPO}/releases/${RELEASE_ID}/attach_files")

if echo "$UPLOAD_RESPONSE" | grep -q '"browser_download_url"'; then
    DOWNLOAD_URL=$(echo "$UPLOAD_RESPONSE" | grep -oE '"browser_download_url":"[^"]+"' | head -1 | cut -d'"' -f4)
    echo "✅ APK 上传成功"
    echo "   下载: $DOWNLOAD_URL"
else
    echo "❌ 上传失败:"
    echo "$UPLOAD_RESPONSE" | head -30
    exit 1
fi

echo ""
echo "🎉 Gitee release 发布完成!"
echo "   https://gitee.com/${GITEE_REPO}/releases/tag/${VERSION_TAG}"
