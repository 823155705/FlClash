class AppTrafficProfileContext {
  final int id;
  final String label;

  const AppTrafficProfileContext({required this.id, required this.label});
}

class AppTrafficDelta {
  final DateTime day;
  final int? hour;
  final int profileId;
  final String profileLabel;
  final String applicationId;
  final String applicationLabel;
  final String processPath;
  final String proxy;
  final String provider;
  final int upload;
  final int download;

  const AppTrafficDelta({
    required this.day,
    this.hour,
    required this.profileId,
    required this.profileLabel,
    required this.applicationId,
    required this.applicationLabel,
    required this.processPath,
    required this.proxy,
    required this.provider,
    required this.upload,
    required this.download,
  });

  int get total => upload + download;

  AppTrafficDelta plus(AppTrafficDelta next) => AppTrafficDelta(
    day: day,
    hour: hour,
    profileId: profileId,
    profileLabel: next.profileLabel,
    applicationId: applicationId,
    applicationLabel: next.applicationLabel,
    processPath: next.processPath,
    proxy: proxy,
    provider: provider,
    upload: upload + next.upload,
    download: download + next.download,
  );
}

typedef AppTrafficBucket = ({
  int index,
  String? applicationId,
  String applicationLabel,
  int upload,
  int download,
});

enum AppTrafficSort {
  total,
  upload,
  download;

  int amount({required int upload, required int download}) => switch (this) {
    AppTrafficSort.total => upload + download,
    AppTrafficSort.upload => upload,
    AppTrafficSort.download => download,
  };
}

class AppTrafficUsage {
  final String applicationId;
  final String applicationLabel;
  final String processPath;
  final int upload;
  final int download;
  final List<String> proxies;
  final List<String> providers;

  const AppTrafficUsage({
    required this.applicationId,
    required this.applicationLabel,
    required this.processPath,
    required this.upload,
    required this.download,
    required this.proxies,
    required this.providers,
  });

  int get total => upload + download;
}
