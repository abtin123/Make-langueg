import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math' as math;
import '../../../core/theme/app_colors.dart';
import '../../map/presentation/destination_provider.dart';
import '../../gps/presentation/gps_providers.dart';
import '../data/place_search_service.dart';
import 'search_providers.dart';

/// دکمهٔ گرد شناور سرچ در نوار پایین. با لمس، جستجوی تمام‌صفحه را باز می‌کند.
class SearchLaunchButton extends ConsumerWidget {
  const SearchLaunchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        ref.read(searchActiveProvider.notifier).state = true;
        if (GoRouterState.of(context).uri.path != '/') {
          context.go('/');
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 55,
        height: 75,
        child: Center(
          child: SizedBox(
            width: 44,
            height: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.subGlassBg(context),
              ),
              child: Icon(
                Icons.search_rounded,
                size: 24,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// لایهٔ کامل جستجو: نوار بالا با اینپوت زنده، و کارت‌های نتیجه با اسلاید
/// که هم روی نقشه پین می‌گذارند و هم گزینهٔ «مسیریابی»/«ارسال» دارند.
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late final PageController _pageController;
  String _lastPinnedResultsKey = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
    _focusNode = FocusNode();
    _pageController = PageController(viewportFraction: 0.88);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _close() {
    ref.read(searchActiveProvider.notifier).state = false;
    ref.read(searchQueryProvider.notifier).state = '';
    _controller.clear();
    _lastPinnedResultsKey = '';
  }

  void _pinSearchResult(PlaceSearchResult place, {bool autoStart = false}) {
    ref.read(selectedDestinationProvider.notifier).state = SelectedDestination(
      place.point,
      label: place.name,
      autoStart: autoStart,
    );
  }

  void _selectPlace(PlaceSearchResult place, {bool startNavigation = false}) {
    _pinSearchResult(place, autoStart: startNavigation);
    _close();
  }

  void _sharePlace(PlaceSearchResult place) {
    final url =
        'https://www.google.com/maps/search/?api=1&query=${place.point.latitude},${place.point.longitude}';
    SharePlus.instance.share(ShareParams(text: url, subject: place.name));
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(searchResultsProvider);
    final selectedIndex = ref.watch(searchSelectedIndexProvider);
    final currentPosition = ref.watch(vehiclePositionProvider).valueOrNull;
    final topInset = MediaQuery.of(context).padding.top;

    return Material(
      color: Colors.black.withOpacity(0.28),
      child: SafeArea(
        child: Column(
          children: [
            // نوار جستجوی بازشده — دقیقاً جای دکمهٔ سرچ کوچک قبلی
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _SearchInputBar(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: (value) =>
                    ref.read(searchQueryProvider.notifier).state = value,
                onBack: _close,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: resultsAsync.when(
                loading: () => _controller.text.trim().length < 2
                    ? const SizedBox.shrink()
                    : const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    AppStrings.literal('خطا در جستجو، دوباره امتحان کنید'),
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                ),
                data: (results) {
                  if (results.isEmpty) return const SizedBox.shrink();

                  // نتیجهٔ اول باید همان لحظه روی نقشه پین شود؛ کاربر لازم
                  // نیست ابتدا کارت را لمس کند. کلید نتایج جلوی اجرای مجدد
                  // این کار در هر rebuild را می‌گیرد.
                  final resultsKey = results
                      .map((place) =>
                          '${place.point.latitude.toStringAsFixed(6)},${place.point.longitude.toStringAsFixed(6)}:${place.name}')
                      .join('|');
                  if (_lastPinnedResultsKey != resultsKey) {
                    _lastPinnedResultsKey = resultsKey;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || results.isEmpty) return;
                      ref.read(searchSelectedIndexProvider.notifier).state = 0;
                      if (_pageController.hasClients) {
                        _pageController.jumpToPage(0);
                      }
                      _pinSearchResult(results.first);
                    });
                  }

                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).padding.bottom + 24,
                      ),
                      child: SizedBox(
                        height: 168,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: results.length,
                          onPageChanged: (index) {
                            ref
                                .read(searchSelectedIndexProvider.notifier)
                                .state = index;
                            // با هر اسلاید، پین و مقصد نقشه هم‌زمان عوض می‌شود.
                            // listener مقصد در HomeScreen دوربین را روی همین
                            // نقطه می‌برد و OnlineMapView پین را در همان نقطه
                            // دوباره projection می‌کند.
                            if (index >= 0 && index < results.length) {
                              _pinSearchResult(results[index]);
                            }
                          },
                          itemBuilder: (context, index) {
                            final place = results[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 8),
                              child: _PlaceResultCard(
                                place: place,
                                index: index,
                                onTapCard: () => _selectPlace(place),
                                distanceMeters: currentPosition == null
                                    ? place.distanceMeters
                                    : _distanceMeters(
                                        currentPosition.lat,
                                        currentPosition.lng,
                                        place.point.latitude,
                                        place.point.longitude,
                                      ),
                                onRoute: () =>
                                    _selectPlace(place, startNavigation: true),
                                onShare: () => _sharePlace(place),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchInputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onBack;

  const _SearchInputBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.glassPanel(context),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.primaryAccent(context).withOpacity(0.55),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryAccent(context).withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_rounded,
                color: AppColors.textPrimary(context)),
            onPressed: onBack,
          ),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: TextStyle(
                    color: AppColors.textPrimary(context), fontSize: 16),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: AppStrings.literal('جستجوی مکان یا آدرس…'),
                  hintStyle: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ),
            ),
          ),
          Container(
            width: 42,
            height: 42,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.primaryGradient(context),
            ),
            child: Icon(Icons.search_rounded,
                color: AppColors.primaryOnAccent(context), size: 22),
          ),
        ],
      ),
    );
  }
}

String _formatDistance(double meters) {
  if (!meters.isFinite || meters < 0) return '';
  if (meters < 1000) return '${meters.round()} m';
  final km = meters / 1000.0;
  final digits = km < 10 ? 1 : 0;
  return '${km.toStringAsFixed(digits)} km';
}

double _distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const radius = 6371000.0;
  final p1 = lat1 * math.pi / 180.0;
  final p2 = lat2 * math.pi / 180.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLng = (lng2 - lng1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1) * math.cos(p2) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
  return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

class _PlaceResultCard extends StatelessWidget {
  final PlaceSearchResult place;
  final int index;
  final VoidCallback onTapCard;
  final double? distanceMeters;
  final VoidCallback onRoute;
  final VoidCallback onShare;

  const _PlaceResultCard({
    required this.place,
    required this.index,
    required this.onTapCard,
    this.distanceMeters,
    required this.onRoute,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapCard,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.glassPanel(context),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppColors.primaryAccent(context).withOpacity(0.3),
          ),
          boxShadow: const [
            BoxShadow(
                color: Colors.black45, blurRadius: 20, offset: Offset(0, 8)),
          ],
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryAccent(context).withOpacity(0.2),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: AppColors.primaryAccent(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        if (distanceMeters != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              _formatDistance(distanceMeters!),
                              style: TextStyle(
                                color: AppColors.primaryAccent(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        if (place.region != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              place.region!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onShare,
                      icon: Icon(Icons.ios_share_rounded,
                          size: 16, color: AppColors.textSecondary(context)),
                      label: Text(AppStrings.literal('ارسال'),
                          style: TextStyle(
                              color: AppColors.textSecondary(context))),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppColors.textSecondary(context)
                                .withOpacity(0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onRoute,
                      icon: const Icon(Icons.alt_route_rounded, size: 18),
                      label: Text(AppStrings.literal('مسیریابی')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryAccent(context),
                        foregroundColor: AppColors.primaryOnAccent(context),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
