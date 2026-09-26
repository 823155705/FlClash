import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: _bindgenEnvironment(input),
    ).run(input: input, output: output);
  });
}

// rquickjs runs bindgen on Android, which must load the NDK's libclang; Linux
// NDKs before r26 keep it under lib64, later ones and every macOS NDK under lib.
// Some macOS NDK builds (e.g. r27) ship no libclang.dylib at all — fall back to
// a host LLVM (Homebrew, CLANG_PATH, or LIBCLANG_PATH) so bindgen can still run.
Map<String, String> _bindgenEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets ||
      input.config.code.targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    return const {};
  }
  final llvmRoot = File.fromUri(compiler).parent.parent;
  for (final name in const ['lib', 'lib64']) {
    final directory = Directory(
      '${llvmRoot.path}${Platform.pathSeparator}$name',
    );
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return {'LIBCLANG_PATH': directory.path};
    }
  }
  final fallback = _hostLibclangPath(llvmRoot.path);
  if (fallback != null) {
    return {'LIBCLANG_PATH': fallback};
  }
  throw StateError(
    'No libclang under ${llvmRoot.path} (lib or lib64) and no host LLVM '
    'fallback; cannot run bindgen for rquickjs',
  );
}

String? _hostLibclangPath(String ndkLlvmRoot) {
  final candidates = <String>[
    if (Platform.environment['LIBCLANG_PATH'] != null)
      Platform.environment['LIBCLANG_PATH']!,
    if (Platform.environment['CLANG_PATH'] != null)
      '${File(Platform.environment['CLANG_PATH']!).parent.parent.path}'
          '${Platform.pathSeparator}lib',
    '/opt/homebrew/opt/llvm/lib',
    '/opt/homebrew/lib',
    '/usr/local/opt/llvm/lib',
    '/usr/lib',
  ];
  for (final path in candidates) {
    final directory = Directory(path);
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return path;
    }
  }
  // NDK lib may contain only compiler-rt; a host llvm-config next to the
  // selected clang is the last resort.
  final sibling = Directory(
    '$ndkLlvmRoot${Platform.pathSeparator}..${Platform.pathSeparator}'
    '..${Platform.pathSeparator}..${Platform.pathSeparator}..',
  );
  if (sibling.existsSync()) {
    for (final entity in sibling.listSync()) {
      if (entity is File && entity.path.endsWith('libclang.dylib')) {
        return entity.parent.path;
      }
    }
  }
  return null;
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}
