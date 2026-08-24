# OCR attribution

Android card-text recognition uses Tesseract4Android 4.9.0, distributed under
the Apache License 2.0:

- https://github.com/adaptech-cz/Tesseract4Android

The bundled English recognition data is `eng.traineddata` from
`tesseract-ocr/tessdata_fast`, also distributed under the Apache License 2.0:

- https://github.com/tesseract-ocr/tessdata_fast
- SHA-256: `7d4322bd2a7749724879683fc3912cb542f19906c83bcc1a52132556427170b2`

This integration is Android-only. The language data lives in Android's native
assets and is not packaged as a cross-platform Flutter asset.
