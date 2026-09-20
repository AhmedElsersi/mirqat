import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/app_info.dart';
import '../../../services/app_info_service.dart';

/// What the about pages show. Null until it has been read; never an error —
/// the service answers with what it has.
class AppInfoCubit extends Cubit<AppInfo?> {
  AppInfoCubit({required AppInfoService appInfoService})
    : _service = appInfoService,
      super(null);

  final AppInfoService _service;

  Future<void> load() async {
    final AppInfo info = await _service.load();
    if (!isClosed) emit(info);
  }
}
