import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkPathKind {
  offline,
  wifi,
  mobile,
  ethernet,
  other,
}

extension NetworkPathKindX on NetworkPathKind {
  bool get isOnline => this != NetworkPathKind.offline;

  String get label => switch (this) {
        NetworkPathKind.offline => 'offline',
        NetworkPathKind.wifi => 'wifi',
        NetworkPathKind.mobile => 'mobile',
        NetworkPathKind.ethernet => 'ethernet',
        NetworkPathKind.other => 'other',
      };

  bool isTransportSwitchTo(NetworkPathKind next) {
    if (!isOnline || !next.isOnline || this == next) {
      return false;
    }
    return (this == NetworkPathKind.wifi && next == NetworkPathKind.mobile) ||
        (this == NetworkPathKind.mobile && next == NetworkPathKind.wifi) ||
        (this == NetworkPathKind.wifi && next == NetworkPathKind.ethernet) ||
        (this == NetworkPathKind.ethernet && next == NetworkPathKind.wifi) ||
        (this == NetworkPathKind.mobile && next == NetworkPathKind.ethernet) ||
        (this == NetworkPathKind.ethernet && next == NetworkPathKind.mobile);
  }
}

NetworkPathKind networkPathKindFromResults(List<ConnectivityResult> results) {
  final unique = results.toSet();
  final onlineResults =
      unique.where((result) => result != ConnectivityResult.none).toSet();

  if (onlineResults.isEmpty) {
    return NetworkPathKind.offline;
  }
  if (onlineResults.contains(ConnectivityResult.wifi)) {
    return NetworkPathKind.wifi;
  }
  if (onlineResults.contains(ConnectivityResult.mobile)) {
    return NetworkPathKind.mobile;
  }
  if (onlineResults.contains(ConnectivityResult.ethernet)) {
    return NetworkPathKind.ethernet;
  }
  return NetworkPathKind.other;
}
