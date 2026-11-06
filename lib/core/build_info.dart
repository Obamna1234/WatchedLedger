/// Filled in by CI with --dart-define; shows "dev" for local builds.
const String kAppVersion =
    String.fromEnvironment('WL_VERSION', defaultValue: 'dev');
const String kGitCommit =
    String.fromEnvironment('WL_COMMIT', defaultValue: 'local');
