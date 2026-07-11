// SmartEye release 脚本回归测试
//
// 目的：防止 release.sh / release-gitee.sh / release-github.sh 关键安全门禁
// 在重构时被人无意移除。
//
// 这些都是 Dart 单元测试，但被测的是 bash 脚本——所以用 File / Process 直接
// 跑 shell，做文本断言。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('release.sh safety guards', () {
    test('refuses to run when not on main branch', () async {
      // 在临时空目录里跑 release.sh，应该报"必须在 main 分支"并退出非 0
      final tmp = await Directory.systemTemp.createTemp('smart_eye_test_');
      try {
        // 拷一个最小 pubspec.yaml 让 release.sh 认为是 Flutter 项目根
        File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: t\n');
        final result = await Process.run(
          'bash',
          ['/Users/pomelo/Project/smart_eye/scripts/release.sh', 'v9.9.9'],
          workingDirectory: tmp.path,
        );
        expect(result.exitCode, isNot(0),
            reason: 'release.sh must exit non-zero on non-main branch');
        expect(result.stdout.toString() + result.stderr.toString(),
            contains('main'));
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('refuses bad tag format', () async {
      // 模拟在 main 分支但 tag 格式错误
      // 用 dry-run 思路：直接调脚本传一个非法 tag，预期报"tag 格式"
      final result = await Process.run(
        'bash',
        ['/Users/pomelo/Project/smart_eye/scripts/release.sh', 'badtag'],
      );
      expect(result.exitCode, isNot(0),
          reason: 'release.sh must reject non-vX.Y.Z tag');
      final combined = result.stdout.toString() + result.stderr.toString();
      expect(combined, contains('vX.Y.Z'));
    });

    test('exposes step 6 (GitHub release) hook', () async {
      // 防 release.sh 的 GitHub release 步骤被无意删除
      final script =
          await File('/Users/pomelo/Project/smart_eye/scripts/release.sh')
              .readAsString();
      expect(script, contains('release-github.sh'),
          reason: 'release.sh must call release-github.sh');
      expect(script, contains('gh auth status'),
          reason: 'release.sh must guard on gh auth status');
      expect(script, contains('步骤 6'),
          reason: 'release.sh step counter must reach 6');
    });

    test('release-gitee.sh CHANGELOG matcher strips v prefix', () async {
      // 防止有人写回 ## [v0.7.2]（实际 CHANGELOG 是 ## [0.7.2]）
      final script =
          await File('/Users/pomelo/Project/smart_eye/scripts/release-gitee.sh')
              .readAsString();
      expect(script, contains(r'local bare="${tag#v}"'),
          reason: 'release-gitee.sh must strip v prefix from CHANGELOG match');
    });

    test('release-gitee.sh supports GITEE_NOTES_FILE', () async {
      final script =
          await File('/Users/pomelo/Project/smart_eye/scripts/release-gitee.sh')
              .readAsString();
      expect(script, contains('GITEE_NOTES_FILE'),
          reason: 'release-gitee.sh must support GITEE_NOTES_FILE override');
    });
  });

  group('release-github.sh safety', () {
    test('file exists and is executable', () async {
      final file =
          File('/Users/pomelo/Project/smart_eye/scripts/release-github.sh');
      expect(await file.exists(), isTrue);
      // 检查 +x 权限
      final stat = await Process.run('stat', ['-f', '%Lp', file.path]);
      final mode = int.tryParse(stat.stdout.toString().trim()) ?? 0;
      expect(mode > 0 && (mode & 0x49) != 0, isTrue,
          reason: 'release-github.sh must be executable (got mode $mode)');
    });

    test('bash syntax is valid', () async {
      final result = await Process.run(
        'bash',
        ['-n', '/Users/pomelo/Project/smart_eye/scripts/release-github.sh'],
      );
      expect(result.exitCode, 0,
          reason: 'release-github.sh must have valid bash syntax');
    });

    test('guards on gh CLI presence', () async {
      // 脚本必须在没装 gh 时给清晰错误（不是默默地 fail）
      final script = await File(
              '/Users/pomelo/Project/smart_eye/scripts/release-github.sh')
          .readAsString();
      expect(script, contains('command -v gh'),
          reason: 'must check gh CLI presence before using it');
      expect(script, contains('gh auth status'),
          reason: 'must check gh login state before uploading');
    });

    test('guards on APK file existence', () async {
      final script = await File(
              '/Users/pomelo/Project/smart_eye/scripts/release-github.sh')
          .readAsString();
      expect(script, contains('APK 文件不存在'),
          reason: 'must check APK file before upload');
    });

    test('uses --clobber on re-upload (idempotent)', () async {
      // 重复跑脚本不应该挂：脚本必须能处理"release 已存在"的情况
      final script = await File(
              '/Users/pomelo/Project/smart_eye/scripts/release-github.sh')
          .readAsString();
      expect(script, contains('clobber'),
          reason: 're-upload path must use --clobber for idempotency');
    });

    test('does NOT hardcode tokens or use curl with env GITHUB_TOKEN',
        () async {
      // 防有人把 token 写进脚本：脚本应该只用 gh CLI（不接触 token 字符串）
      final script = await File(
              '/Users/pomelo/Project/smart_eye/scripts/release-github.sh')
          .readAsString();
      expect(script.contains('GITHUB_TOKEN'), isFalse,
          reason:
              'release-github.sh must NOT read GITHUB_TOKEN env (use gh auth)');
      // 脚本里可以用 gh 命令；但不能用 `curl` 直接调 GitHub API（那样会暴露 token）
      // 用一个简单启发：脚本中不出现 `curl -X` 或 `curl ... Authorization`
      expect(script.contains('curl -X'), isFalse,
          reason:
              'must not call GitHub API via curl with -X (avoids token in argv)');
      expect(script.contains('Authorization'), isFalse,
          reason: 'must not pass Authorization header (token leak risk)');
    });

    test('supports GITHUB_NOTES_FILE for custom release body', () async {
      // v0.7.2 release body 修复：必须能传外部 markdown 文件（避免 JSON 转义）
      final script = await File(
              '/Users/pomelo/Project/smart_eye/scripts/release-github.sh')
          .readAsString();
      expect(script, contains('GITHUB_NOTES_FILE'),
          reason: 'release-github.sh must support GITHUB_NOTES_FILE override');
    });

    test('pins release to tag commit (not main HEAD)', () async {
      // v0.7.2 release target_commitish 修复：必须用 `git rev-list -n 1` 钉到 tag
      // 指向的 commit，否则 main 推进时 release 会自动跟踪
      final script = await File(
              '/Users/pomelo/Project/smart_eye/scripts/release-github.sh')
          .readAsString();
      expect(script, contains('git rev-list -n 1'),
          reason: 'release-github.sh must pin target to tag commit');
      expect(script.contains('--target "main"'), isFalse,
          reason:
              'release-github.sh must not default to "main" (gets auto-tracked)');
      expect(script.contains('--target main'), isFalse,
          reason: 'hardcoded --target main is forbidden');
    });
  });

  group('release-gitee.sh unchanged behavior', () {
    test('file still exists and is executable', () async {
      final file =
          File('/Users/pomelo/Project/smart_eye/scripts/release-gitee.sh');
      expect(await file.exists(), isTrue);
      final stat = await Process.run('stat', ['-f', '%Lp', file.path]);
      final mode = int.tryParse(stat.stdout.toString().trim()) ?? 0;
      expect(mode > 0 && (mode & 0x49) != 0, isTrue,
          reason: 'release-gitee.sh must be executable (got mode $mode)');
    });

    test('bash syntax is valid', () async {
      final result = await Process.run(
        'bash',
        ['-n', '/Users/pomelo/Project/smart_eye/scripts/release-gitee.sh'],
      );
      expect(result.exitCode, 0);
    });
  });
}
