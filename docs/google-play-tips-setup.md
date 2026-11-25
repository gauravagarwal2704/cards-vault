# Google Play supporter tips setup

CardVault uses Google Play Billing for optional Supporter Stars. Every purchase
adds one cosmetic Supporter Star to the supporter page. No functional CardVault
feature is restricted or unlocked.

## Create the products

In Play Console, open **Monetize with Play > Products > One-time products** and
create these product IDs:

| Product ID | Suggested India price |
| --- | ---: |
| `support_tip_1` | ₹29 |
| `support_tip_2` | ₹49 |
| `support_tip_3` | ₹99 |
| `support_tip_4` | ₹149 |
| `support_tip_5` | ₹249 |
| `support_tip_6` | ₹499 |
| `support_tip_7` | ₹999 |

For every product:

1. Use a name such as **CardVault Supporter Star** and explain that the digital
   item adds one cosmetic star to the app's supporter page.
2. Add a **Buy** purchase option, configure regional availability and review
   Google's converted regional prices.
3. Activate the product.
4. Treat it as consumable. The app calls the consumable purchase flow so the
   same Supporter Star can be purchased again.

The app queries Google Play for localized prices. Do not hard-code currency
amounts in the app. The first, third, and fifth configured price tiers appear
as quick amounts; **More amounts** shows every available configured tier as a selectable option.
Google Play Billing cannot accept an arbitrary price that is absent from the
Play product catalog.

## Test before release

1. Upload an Android App Bundle containing this implementation to an internal
   or closed testing track.
2. Add tester Google accounts under **Settings > License testing** and opt those
   accounts into the test track.
3. Install CardVault from the Play testing link. A sideloaded debug APK usually
   cannot retrieve the production product catalog.
4. Open **Settings**, tap the CardVault icon or **Support**, and verify that all
   localized prices load.
5. Test successful, cancelled, failed, and pending purchases with Google's test
   payment instruments.
6. Verify that a completed tip can be purchased again. Consumable purchases
   must be completed promptly or Google Play can refund them automatically.

## Policy and data disclosures

- Describe each Play product accurately as a digital **Supporter Star**, not a
  tax-exempt donation.
- Google treats a pure contribution that grants no digital item as a
  peer-to-peer payment, for which Play Billing must not be used. The locally
  displayed Supporter Star is the digital item purchased here.
- Do not promise preferential access or supporter-only functional features.
  Future improvements mentioned in the UI are for every user.
- Payment-card details are collected directly by Google Play and are never
  available to CardVault.
- CardVault receives the selected product ID and transient purchase status but
  does not persist purchase history or send purchase tokens to a developer
  backend. It stores only an aggregate Supporter Star count on the device.
- Review the Play Console Data safety answers after every billing SDK or payment
  architecture change. Under Google's payment-service exception, payment-card
  data collected directly by Google Play does not need to be declared as data
  collected by CardVault when the app never accesses it. Reassess **Purchase
  history** if transaction data is later retained or sent to a backend.
- Publish the updated policy in `docs/privacy-policy.html` at the privacy-policy
  URL before submitting this build for review.

## Release checklist

- Confirm all seven products are active in every intended country.
- Confirm the merchant/payments profile and tax information are complete.
- Use Play Console order management to test refunds.
- Keep the support flow optional and outside onboarding or core card workflows.
- Keep the purchased digital item and Play Console description synchronized.
