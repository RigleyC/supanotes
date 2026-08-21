import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

final FutureProvider<PackageInfo> appPackageInfoProvider = FutureProvider.autoDispose<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
