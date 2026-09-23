import '../../../core/localization/app_localizations.dart';

import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:abtin_maps/core/geo/geo_types.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/bottom_nav.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/page_header.dart';
import '../../gps/presentation/gps_providers.dart';
import '../../map/presentation/destination_provider.dart';
import 'saved_places_providers.dart';

class _CategoryMeta {
  final String label;
  final IconData icon;
  const _CategoryMeta(this.label, this.icon);
}

const Map<String, _CategoryMeta> _categoryMeta = {
  'home': _CategoryMeta('خانه', Icons.home_rounded),
  'work': _CategoryMeta('محل کار', Icons.work_rounded),
  'favorite': _CategoryMeta('سایر', Icons.star_rounded),
  'recent': _CategoryMeta('اخیر', Icons.history_rounded),
};

_CategoryMeta _metaFor(String category) =>
    _categoryMeta[category] ?? const _CategoryMeta('سایر', Icons.star_rounded);

// برچسب دسته‌بندی را با توجه به زبان انتخاب‌شده برمی‌گرداند (متن ثابت بالا
// فقط برای fallback و آیکون استفاده می‌شود).
String _categoryLabel(BuildContext context, WidgetRef ref, String category) {
  switch (category) {
    case 'home':
      return AppStrings.get(context, ref, 'category_home');
    case 'work':
      return AppStrings.get(context, ref, 'category_work');
    case 'recent':
      return AppStrings.get(context, ref, 'category_recent');
    default:
      return AppStrings.get(context, ref, 'category_other');
  }
}

class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(savedPlacesListProvider);

    return Scaffold(
      appBar: PageHeader(
          title: AppStrings.get(context, ref, 'saved_places_title'),
          backRoute: '/settings'),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: [
              AppColors.primaryAccent(context).withOpacity(0.075),
              AppColors.background(context),
            ],
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              child: placesAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: AppColors.subAccentA(context),
                  ),
                ),
                error: (e, st) => Center(
                  child: Text(
                    '${AppStrings.get(context, ref, 'db_error')}: $e',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary(context),
                        ),
                  ),
                ),
                data: (places) {
                  if (places.isEmpty) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(AppStrings.get(context, ref, 'no_places_yet'),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary())),
                        const SizedBox(height: 20),
                        _AddPlaceButton(
                          label: AppStrings.get(context, ref, 'add_new_place'),
                          onTap: () => _showAddDialog(context, ref),
                        ),
                      ],
                    );
                  }

                  final grouped = <String, List<SavedPlace>>{};
                  for (final p in places) {
                    grouped.putIfAbsent(p.category, () => []).add(p);
                  }
                  final orderedKeys = ['home', 'work', 'favorite', 'recent']
                      .where((k) => grouped.containsKey(k))
                      .toList()
                    ..addAll(grouped.keys.where((k) =>
                        !['home', 'work', 'favorite', 'recent'].contains(k)));

                  return ListView(
                    children: [
                      for (final key in orderedKeys) ...[
                        _CategoryHeader(
                          meta: _metaFor(key),
                          label: _categoryLabel(context, ref, key),
                          count: grouped[key]!.length,
                          countSuffix: AppStrings.get(
                              context, ref, 'place_count_suffix'),
                          deleteLabel: AppStrings.get(
                              context, ref, 'delete_this_category'),
                          onDeleteAll: () => _confirmDeleteCategory(
                              context, ref, grouped[key]!),
                        ),
                        const SizedBox(height: 12),
                        for (final place in grouped[key]!) ...[
                          _PlaceCard(
                            place: place,
                            deleteLabel: AppStrings.get(
                                context, ref, 'delete_this_place'),
                            deleteShortLabel:
                                AppStrings.get(context, ref, 'delete_short'),
                            navigateLabel:
                                AppStrings.get(context, ref, 'navigate_label'),
                            editLabel:
                                AppStrings.get(context, ref, 'edit_label'),
                            shareLabel:
                                AppStrings.get(context, ref, 'share_label'),
                            cancelLabel: AppStrings.get(context, ref, 'cancel'),
                            onNavigate: () {
                              ref
                                  .read(selectedDestinationProvider.notifier)
                                  .state = SelectedDestination(
                                LatLng(place.latitude, place.longitude),
                                label: place.name,
                                autoStart: true,
                              );
                              context.go('/');
                            },
                            onEdit: () => _showEditDialog(context, ref, place),
                            onShare: () => _sharePlace(place),
                            onDelete: () => ref
                                .read(savedPlacesRepositoryProvider)
                                .remove(place.id),
                          ),
                          const SizedBox(height: 14),
                        ],
                        const SizedBox(height: 8),
                      ],
                      _AddPlaceButton(
                        label: AppStrings.get(context, ref, 'add_new_place'),
                        onTap: () => _showAddDialog(context, ref),
                      ),
                    ],
                  );
                },
              ),
            ),
            const BottomNav(currentPage: NavKey.saved),
          ],
        ),
      ),
    );
  }

  void _sharePlace(SavedPlace place) {
    final link =
        'https://www.openstreetmap.org/?mlat=${place.latitude}&mlon=${place.longitude}#map=17/${place.latitude}/${place.longitude}';
    final text =
        '${place.name}${place.address != null ? '\n${place.address}' : ''}\n$link';
    SharePlus.instance.share(ShareParams(text: text, subject: place.name));
  }

  void _confirmDeleteCategory(
      BuildContext context, WidgetRef ref, List<SavedPlace> places) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(
          AppStrings.get(context, ref, 'delete_category_dialog_title'),
          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary(ctx),
              ),
        ),
        content: Text(
          '${AppStrings.get(context, ref, 'delete_category_confirm_prefix')} ${places.length} ${AppStrings.get(context, ref, 'delete_category_confirm_suffix')}',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.textSecondary()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.get(context, ref, 'cancel'))),
          TextButton(
            onPressed: () async {
              for (final p in places) {
                await ref.read(savedPlacesRepositoryProvider).remove(p.id);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(AppStrings.get(context, ref, 'delete_all'),
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: const Color(0xFFFF6B81))),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(
          AppStrings.get(context, ref, 'add_current_location_title'),
          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary(ctx),
              ),
        ),
        content: TextField(
          controller: nameController,
          textAlign: TextAlign.right,
          style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                color: AppColors.textPrimary(ctx),
              ),
          decoration: InputDecoration(
            hintText: AppStrings.get(context, ref, 'place_name_hint'),
            hintStyle: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary(ctx),
                ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.get(context, ref, 'cancel'))),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final pos = ref.read(vehiclePositionProvider).valueOrNull;
              if (pos == null) {
                Navigator.pop(ctx);
                return;
              }
              await ref.read(savedPlacesRepositoryProvider).add(
                    name: name,
                    latitude: pos.lat,
                    longitude: pos.lng,
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(AppStrings.get(context, ref, 'save_current_location')),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, SavedPlace place) {
    final nameController = TextEditingController(text: place.name);
    final addressController = TextEditingController(text: place.address ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(
          AppStrings.get(context, ref, 'edit_place_title'),
          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                color: AppColors.textPrimary(ctx),
              ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              textAlign: TextAlign.right,
              style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textPrimary(ctx),
                  ),
              decoration: InputDecoration(
                hintText: AppStrings.get(context, ref, 'place_name_hint2'),
                hintStyle: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary(ctx),
                    ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: addressController,
              textAlign: TextAlign.right,
              style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(
                    color: AppColors.textPrimary(ctx),
                  ),
              decoration: InputDecoration(
                hintText: AppStrings.get(context, ref, 'address_optional_hint'),
                hintStyle: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary(ctx),
                    ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppStrings.get(context, ref, 'cancel'))),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              await ref.read(savedPlacesRepositoryProvider).rename(
                    id: place.id,
                    name: name,
                    address: addressController.text.trim().isEmpty
                        ? null
                        : addressController.text.trim(),
                  );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(AppStrings.get(context, ref, 'save_label')),
          ),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final _CategoryMeta meta;
  final String label;
  final int count;
  final String countSuffix;
  final String deleteLabel;
  final VoidCallback onDeleteAll;

  const _CategoryHeader({
    required this.meta,
    required this.label,
    required this.count,
    required this.countSuffix,
    required this.deleteLabel,
    required this.onDeleteAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: AppColors.textSecondary()),
          color: const Color(0xFF14181D),
          onSelected: (v) {
            if (v == 'delete') onDeleteAll();
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
                value: 'delete',
                child: Text(deleteLabel,
                    style: const TextStyle(color: Color(0xFFFF6B81)))),
          ],
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: AppColors.textPrimary(context))),
              Text('$count $countSuffix',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.textSecondary())),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.primaryGradient(context),
          ),
          child: Icon(
            meta.icon,
            color: AppColors.primaryOnAccent(context),
            size: 22,
          ),
        ),
      ],
    );
  }
}

class _PlaceCard extends StatelessWidget {
  final SavedPlace place;
  final String deleteLabel;

  /// برچسب کوتاه دکمهٔ حذف روی کارت — فقط «حذف»، بدون هیچ متن اضافه.
  final String deleteShortLabel;
  final String navigateLabel;
  final String editLabel;
  final String shareLabel;
  final String cancelLabel;
  final VoidCallback onNavigate;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _PlaceCard({
    required this.place,
    required this.deleteLabel,
    required this.deleteShortLabel,
    required this.navigateLabel,
    required this.editLabel,
    required this.shareLabel,
    required this.cancelLabel,
    required this.onNavigate,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
  });

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(deleteLabel,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: AppColors.textPrimary(context))),
        content: Text(place.name,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondary())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(cancelLabel)),
          TextButton(
            onPressed: () {
              onDelete();
              Navigator.pop(ctx);
            },
            child: Text(deleteLabel,
                style: const TextStyle(color: Color(0xFFFF6B81))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.star_rounded,
                    color: Color(0xFFF4C230), size: 22),
                color: const Color(0xFF14181D),
                onSelected: (v) {
                  if (v == 'navigate') onNavigate();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'navigate',
                    child: Text(navigateLabel,
                        style: TextStyle(color: AppColors.subAccentA(context))),
                  ),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text(deleteShortLabel,
                          style: const TextStyle(color: Color(0xFFFF6B81)))),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(place.name,
                          textAlign: TextAlign.right,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                  color: AppColors.textPrimary(context))),
                      if (place.address != null &&
                          place.address!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(place.address!,
                            textAlign: TextAlign.right,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary())),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.subGlassBgSoft(),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  color: AppColors.subAccentA(context),
                  size: 26,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
              color: AppColors.textPrimary(context).withOpacity(.08),
              height: 1),
          // نکته: قبلاً برچسب حذف «حذف این مکان» بود و همین باعث سرریز
          // ردیف و ناپدید شدن دکمهٔ «مسیریابی» در فارسی می‌شد.
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                    icon: Icons.navigation_rounded,
                    label: navigateLabel,
                    onTap: onNavigate),
              ),
              Expanded(
                child: _ActionButton(
                    icon: Icons.edit_rounded, label: editLabel, onTap: onEdit),
              ),
              Expanded(
                child: _ActionButton(
                    icon: Icons.ios_share_rounded,
                    label: shareLabel,
                    onTap: onShare),
              ),
              Expanded(
                child: _ActionButton(
                  icon: Icons.delete_outline_rounded,
                  label: deleteShortLabel,
                  color: const Color(0xFFFF6B81),
                  onTap: () => _confirmDelete(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.subAccentA(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: c)),
                const SizedBox(width: 6),
                Icon(icon, color: c, size: 17),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddPlaceButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddPlaceButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.subAccentB(context), width: 1.5),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.subAccentA(context),
                fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
