# TODO

- [x] Wire `lib/shared/widgets/bottom_nav.dart` to `AppearanceSettings`
      (`bottomNavBackgroundColor`, `bottomNavBorderColor`, `bottomNavGlowColor`,
      `bottomNavIconColor`, `bottomNavIconActiveColor`, `bottomNavHomeButtonColor`,
      `bottomNavOpacity`) via `ref.watch(appearanceSettingsProvider)`.
- [x] Add settings-screen UI:
  - [x] Route card: color pickers for `routeCardBackgroundColor`,
        `routeCardBorderColor`, `routeCardGlowColor` in `_RouteCardSettingsCard`
        (`appearance_settings_screen.dart`).
  - [x] New "منوی پایین" `_GlassCard` section (`_BottomNavSettingsCard`) with
        color pickers/opacity slider for the new `bottomNav*` fields, with a
        live `BottomNav` preview embedded at the top of the card.
  - [x] Added corresponding read/write `_SyncedField` providers in
        `appearance_settings_providers.dart` for `routeCardBackgroundColor`,
        `routeCardBorderColor`, `routeCardGlowColor`, and all `bottomNav*`
        fields.
- [x] Remove the MBTiles/cache-rebuild dependency from offline map activation.
- [x] Treat `.abm` only as the transport container and extract `map.sqlite` +
      `metadata.json` once into the app's map data directory.
- [x] Read offline search, routing, POI and viewport road data directly from the
      extracted canonical `map.sqlite` with SQLite indexes/file-backed access.
- [x] Remove MBTiles artifacts and MBTiles probes from the active offline path.
- [x] Make offline map style use SQLite-backed GeoJSON sources instead of a
      secondary tile database.
- [x] Keep search home-only: tapping Search on any other page first navigates to
      Home and then opens the search overlay there.
- [x] Separate voice mute/unmute state from BottomNav active-state animation.
      Voice becomes active only on the voice-settings page.
- [x] Long-pressing the Voice nav item opens `/voice-settings`; that page marks
      the Voice item active instead of the Settings item.
- [ ] Verify project with `flutter analyze` and `flutter build` on a machine
      with the Flutter/Dart toolchain.
- [ ] Run an on-device offline IR.abm smoke test: extraction, map viewport,
      POI rendering, search and routing.
- [x] Move the active route guidance card to the top of the map area and make
      its height content-aware so enlarged fonts cannot escape the card.
- [x] Make route-card appearance controls live through the single
      `AppearanceSettings` state used by both preview and real navigation.
- [x] Fix roundabout layer order so the roundabout ring is drawn over all
      entrance/exit branches; enlarge the inner hole and place the active exit
      number inside it.
- [x] Remove hard-coded roundabout branch colors/opacities so the corresponding
      appearance settings actually affect the real maneuver icon.
- [ ] Validate real roundabout geometry against IR.abm junctions: exact physical
      arm count, entrance/exit classification, active exit angle/number, U-turn
      classification, and curved off-ramp geometry at bridge/interchange cases.
- [x] Apply the same geometry-first maneuver classification to online OSRM
      instructions: exact roundabout arm bearings from `intersections`, active
      exit bearing, shallow left/right correction and geometry-based U-turn
      correction.
- [x] Move route-card close button beside the lower route statistics and free the
      upper instruction area; compact overlong maneuver text instead of shrinking
      the whole sentence to unreadable size.
- [x] Replace the offline roundabout's fixed four-branch drawing with branch
      bearings discovered from the canonical `map.sqlite` routing graph.
