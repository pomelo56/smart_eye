#!/bin/bash
# GitHub Release 发布器
# 用法: ./scripts/release-github.sh <version-tag> <apk-path>
#
# 必设环境变量: 无（依赖 `gh` CLI 已登录）
#   $ gh auth login                          # 浏览器登录
#   $ gh auth login --with-token < token.txt # 粘贴 token 登录
#   $ gh auth status                          # 验证已登录
# 可设环境变量:
#   GITHUB_REPO - 仓库路径 (默认 pomelo56/smart_eye)
#
# 设计说明:
# - 不引入 curl + token 直连 GitHub API（避免 token 误入 commit 历史 / 日志）
# - 依赖 gh CLI，gh 自己处理 token 缓存（~/.config/gh/hosts.yml）
# - 找不到 gh CLI 或未登录则报错并退出 2，调用方可判断跳过

set -e

if [ $# -ne 2 ]; then
    echo "❌ 用法: $0 <version-tag> <apk-path>"
    exit 1
fi

VERSION_TAG="$1"
APK_PATH="$2"

# ====== 1. 环境检查 ======
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ 错误: 找不到 gh CLI"
    echo "   安装: brew install gh"
    exit 2
fi

# gh auth status 失败时退出码为 1；用 >/dev/null 2>&1 + 单独捕获
if ! gh auth status >/dev/null 2>&1; then
    echo "❌ 错误: gh CLI 未登录"
    echo "   登录: gh auth login --web  # 弹浏览器"
    echo "   或:   gh auth login --with-token < token.txt"
    echo "   验证: gh auth status"
    exit 2
fi

if [ ! -f "$APK_PATH" ]; then
    echo "❌ 错误: APK 文件不存在: $APK_PATH"
    exit 1
fi

GITHUB_REPO="${GITHUB_REPO:-pomelo56/smart_eye}"

# ====== 2. 从 CHANGELOG.md 提取本版本说明 ======
extract_changelog() {
    local tag="$1"
    local changelog="CHANGELOG.md"
    if [ ! -f "$changelog" ]; then
        echo "Release $tag"
        return
    fi
    # tag 形如 v0.7.2，CHANGELOG 形如 ## [0.7.2] — YYYY-MM-DD (标题)
    # 使用 index() 做字符串精确匹配，避免 [ / ] 在正则中被当作字符类
    local bare="${tag#v}"
    local header="## [$bare]"
    awk -v header="$header" '
        index($0, header) == 1 { capture=1; next }
        capture && /^## \[/ { exit }
        capture { print }
    ' "$changelog" | head -c 4000
}

# 从 CHANGELOG.md 提取本版本的标题（用于 release name）
# 格式: ## [0.8.3] — 2026-07-10 (应用内更新正式版) → "v0.8.3 — 应用内更新正式版"
extract_release_name() {
    local tag="$1"
    local changelog="CHANGELOG.md"
    if [ ! -f "$changelog" ]; then
        echo "$tag"
        return
    fi
    local bare="${tag#v}"
    local header="## [$bare]"
    local title_line
    title_line=$(awk -v header="$header" 'index($0, header) == 1 { print; exit }' "$changelog")
    local subtitle
    subtitle=$(echo "$title_line" | sed -E "s/^## \[$bare\][^—]*— [0-9]{4}-[0-9]{2}-[0-9]{2} \((.+)\)$/\1/")
    if [ -n "$subtitle" ] && [ "$subtitle" != "$title_line" ]; then
        echo "$tag — $subtitle"
    else
        echo "$tag"
    fi
}

RELEASE_BODY=$(extract_changelog "$VERSION_TAG")
RELEASE_NAME=$(extract_release_name "$VERSION_TAG")
# 如果设置了 GITHUB_NOTES_FILE，直接从文件读 release body（优先级最高，
# 便于传带换行/emoji/引号的中文 markdown note）
if [ -n "${GITHUB_NOTES_FILE:-}" ] && [ -f "$GITHUB_NOTES_FILE" ]; then
    RELEASE_BODY=$(cat "$GITHUB_NOTES_FILE")
elif [ -z "$RELEASE_BODY" ]; then
    RELEASE_BODY="详见 [CHANGELOG.md](https://github.com/${GITHUB_REPO}/blob/${VERSION_TAG}/CHANGELOG.md)"
fi

APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
APK_NAME="smart_eye-${VERSION_TAG}.apk"

# ====== 3. 查 release 是否已存在 ======
echo ""
echo "🔍 查找 release: $VERSION_TAG"

if gh release view "$VERSION_TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    echo "✅ Release 已存在，将上传/替换 APK 资产并更新标题/描述"
    # 已有 release：更新标题和描述，先删旧 APK（如果存在），再传新的
    gh release edit "$VERSION_TAG" --repo "$GITHUB_REPO" --title "$RELEASE_NAME" --notes "$RELEASE_BODY"
    gh release delete-asset "$VERSION_TAG" "$APK_NAME" --repo "$GITHUB_REPO" >/dev/null 2>&1 || true
    UPLOAD_ARGS=(upload "$VERSION_TAG" "$APK_PATH" --repo "$GITHUB_REPO"
                 --clobber)
else
    echo "📦 创建 GitHub release: $RELEASE_NAME"
    # 把 release 钉死到 tag 指向的 commit（而不是 main 分支当前 HEAD），
    # 否则下次 main 推进时，这个 release 的 target_commitish 会被自动跟踪，
    # 破坏 release ↔ commit 的一一对应关系。
    target_commit=$(git rev-list -n 1 "$VERSION_TAG" 2>/dev/null || echo "main")
    UPLOAD_ARGS=(release create "$VERSION_TAG" "$APK_PATH"
                 --repo "$GITHUB_REPO"
                 --title "$RELEASE_NAME"
                 --notes "$RELEASE_BODY"
                 --target "$target_commit")
fi

# ====== 4. 上传 APK ======
echo ""
echo "📎 上传 APK ($APK_SIZE) 到 $GITHUB_REPO..."

if gh "${UPLOAD_ARGS[@]}"; then
    echo "✅ APK 上传成功"
    echo "   Release: https://github.com/${GITHUB_REPO}/releases/tag/${VERSION_TAG}"
else
    echo "❌ 上传失败"
    exit 1
fi

echo ""
echo "🎉 GitHub release 发布完成!"
echo "   https://github.com/${GITHUB_REPO}/releases/tag/${VERSION_TAG}"
