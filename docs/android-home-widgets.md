# Android home-screen widgets

Introduced in 1.9.0+39. Long-press your home screen and choose Card Vault grid,
Card Vault compact square, or Card Vault vertical from Widgets. Place it and
tap Choose cards. Complete onboarding and unlock the app if required. Select
up to four cards in display order, then save. Each placed
widget has its own selection; tap Edit to change it.
Resize with the launcher's handles. Every face keeps the 85.60:53.98 credit-card
ratio. The layout uses actual widget bounds to choose one large card, a row,
a column, or a grid. All selected cards stay visible, scaling down together when
space is reduced.
Smaller widgets ellipsize long names and nicknames. Actual dimensions depend
on the launcher grid. There is no automatic usage ranking in this release.

As of 1.14.0+47, the widget picker includes a compact square with a 2×2 cell
target. Its shorter header and smaller card spacing fit four smaller cards in
two rows. It has its own card selection and uses the same secure previews and
card deep links. If resized to a wide or tall shape, it rearranges the cards.

As of 1.13.0+46, Android's widget picker added separate grid and vertical
entries. The grid widget starts at a 3×3 cell target with four cards in two rows. The vertical
widget starts at a 2×4 cell target with equal-sized cards in one column. The
two-cell width keeps the bank logos, nicknames and Edit action readable. Each
placed widget keeps its own card order.
The grid rearranges cards as it is resized; the vertical widget keeps one
equal-sized column and scales its cards. Both use the same protected card
previews and tap destinations.

As of 1.12.3+45, a tall widget reflows to a single vertical card list when
the 2×2 grid would leave substantial unused height. All selected cards stay
visible with their credit-card proportions. The list uses the available height
and leaves wider side margins around its narrower cards.

As of 1.12.2+44, the widget header reads “Card Vault” and shows the app icon
selected in Appearance. Changing the app icon refreshes placed widgets.

As of 1.12.0+42, selected card previews always display the cardholder name
(or profile name), bank logo when available (otherwise the bank name), nickname
when present, last four digits and network logo. The same saved design,
gradient, or contained custom image background appears as on the in-app card.
The full card number, expiry, CVV, notes, and attachments are never copied to
the widget. Selecting a card makes its preview and any details within a custom
background visible outside app lock, including in launcher screenshots.

As of 1.12.1+43, the widget panel fills its resize bounds. Cards remain at the
85.60:53.98 ratio, with 8 dp between neighbors and 10 dp from the panel sides.
The card group starts just below the header so a taller widget does not gain a
large empty band above its cards. Fixed-ratio cards cannot fill every tall
widget shape without becoming smaller or leaving spare room below the last row.

## Data and security

- Native RemoteViews use an explicit MethodChannel; no new plugin, networking,
  background job, or exported deep-link intent filter is introduced.
- Each immutable PendingIntent explicitly targets MainActivity. Its URI contains
  only a card ID or widget ID. URI identity separates card taps across widgets.
- Validate destinations in Kotlin and Dart. Queue launches through startup,
  onboarding and app lock, then reload cards from authoritative secure storage.
  A missing card opens the wallet with a message rather than stale card data.
- The entire Navigator is covered and excluded from semantics while locked.
  Existing routes remain mounted, and their tickers pause. Failed/cancelled
  authentication leaves the lock in place and allows an explicit retry.
- The native receivers are not exported. Their preferences are private,
  credential-protected, excluded from backup by the app's backup policy, and
  contain selected IDs and bounded previews. Bank labels and logo assets come
  from the built-in bank catalog.
- Cardholder/profile names, sanitized nicknames, bank labels, validated four-digit
  suffixes and normalized network labels are persisted only for selected cards.
  Flutter decrypts holder names only for IDs requested by the active widget
  registry. Names and nicknames are bounded; long digit sequences and controls
  are stripped. Never share full card objects, encrypted records/keys, full
  saved number/expiry/CVV fields, notes or attachments. Custom images require a
  contained private path; their contents are visible outside app lock.
- Card artwork is rendered in memory with a bitmap budget shared across every
  responsive size/orientation, then displayed with aspect-preserving ImageViews.
  Small encoded background, bank-logo and network-logo thumbnails are kept in the private widget cache.
  No original image paths are shared. Updates fully replace RemoteViews.
  Widget content cannot inherit FLAG_SECURE
  from the app: launcher content and screenshots may expose selected previews.
- Storage mutation attempts trigger a serialized refresh, including partial
  failures. Card deletion prunes selections. A failed read clears preview
  metadata, retains IDs for retry, and shows generic labels. Removing/restoring
  widgets clears their settings.
- Refreshes are event driven, without periodic wakeups. Startup in an unlocked
  wallet reconciles the native cache after a process interruption.

## Validation

Automated coverage checks URI rejection, snapshot allowlisting, startup gates,
cold/warm configuration links, app lock across pushed routes, secure storage,
and synchronized release records. Android APK compilation checks Kotlin and XML.

Verified on 28 October 2026: all 230 Flutter tests and nine native layout/security
tests passed. Final static analysis
reported no issues, and the Android debug APK compiled. Real RemoteViews were
inflated and visually checked with four synthetic cards at compact, square, tall
and wide sizes. The native tests cover fit and fixed proportions across thousands
of sizes, retaining every selected card, and Unicode name
sanitization. The latest checks also validate shared saved-design artwork, real
network-logo assets, isolation from card fields, tighter packing, and bitmap
density for older Android launchers. Synthetic RemoteViews were also inspected
at square, tall, wide and compact sizes with bank logos and nicknames. Run native
checks with `cd android && ./gradlew :app:testDebugUnitTest`. On an Android 14 emulator,
the widget appeared in the picker, placed on the home screen, and its setup tap
cold-started the app directly into Customize widget. Authentication, warm
configuration taps, relocking, switching between saved card destinations, and
missing-card recovery were verified by automated navigation tests.

Additional device/launcher checks before shipping:

1. Add all three widget types and select different cards in different orders. Verify each
   widget displays only its selected card previews.
2. Resize square → wide → tall and rotate. Check narrow bounds, large text,
   empty selection, one to four selected cards, and readable touch targets.
3. Tap each card with the app closed, unlocked, locked, and already displaying
   another card. Confirm the correct card and normal Back navigation.
4. Cancel authentication, retry, and background beyond the lock timeout on a
   card/settings screen. Ensure content and accessibility stay covered.
5. Edit/delete selected cards, delete the wallet, and replace/merge a backup.
   Check that labels refresh and removed card IDs cannot open cached content.
6. Remove a widget, restart the launcher/device, and repeat on Android 8–11 and
   Android 12+ launchers. Preview data must never be restored to a new widget ID.
