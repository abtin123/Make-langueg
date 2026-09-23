import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/presentation/appearance_settings_providers.dart';
import 'system_info_widget.dart';

class SystemInfoMapOverlay extends ConsumerWidget {
  const SystemInfoMapOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceSettingsProvider);
    if (!appearance.systemInfoEnabled) return const SizedBox.shrink();

    final vertical = appearance.systemInfoVerticalPercent.clamp(0.0, 100.0);
    final horizontal = appearance.systemInfoHorizontalPercent.clamp(0.0, 100.0);
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          MediaQuery.of(context).padding.top + 12,
          12,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        child: Align(
          alignment: Alignment(
            horizontal / 50.0 - 1,
            vertical / 50.0 - 1,
          ),
          child: SystemInfoWidget(
            scale: appearance.systemInfoSize / 100.0,
            background: appearance.systemInfoBgColor
                .withOpacity(appearance.systemInfoBgOpacity),
            textColor: appearance.systemInfoTextColor,
            contentAlign: appearance.systemInfoContentAlign,
            batteryOrientation: appearance.systemInfoBatteryOrientation,
            batterySizePercent: appearance.systemInfoBatterySizePercent,
            batteryColor: appearance.systemInfoBatteryColor,
          ),
        ),
      ),
    );
  }
}
