# Local Android CardScan runtime

This directory contains the Android camera, OCR model, and local LiteRT
adapter code derived from Stripe Android SDK `v21.28.1`.

Only the offline CardScan pipeline is compiled. The Stripe networking,
analytics/diagnostic reporter, payment modules, Dagger graph, fragment API,
and `INTERNET` permission are intentionally excluded. The scanner uses the
standalone `com.google.ai.edge.litert:litert` runtime rather than the Google
Play Services runtime. It uses
CameraX `ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST`, requires agreement across
three Luhn-valid PAN detections, and has a 20-second session timeout.

Among PAN-positive preview frames, only the sharpest matching crop is retained
in memory. That single accepted crop is written losslessly and temporarily so
the app's local Tesseract pass can attempt expiry and cardholder-name
extraction. Rejected preview frames are recycled after inference, and the
temporary accepted crop is deleted immediately after text OCR.

Upstream: https://github.com/stripe/stripe-android/tree/v21.28.1

License: Stripe's MIT license is included in `LICENSE`.
