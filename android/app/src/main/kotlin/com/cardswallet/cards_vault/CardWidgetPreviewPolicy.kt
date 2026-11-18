package com.cardswallet.cards_vault

/** Last defence for selected card labels before persisting launcher previews. */
object CardWidgetPreviewPolicy {
    fun name(value: String) = value.replace(Regex("[^\\p{L}\\p{M} .’'-]"), "")
        .trim().replace(Regex(" +"), " ").take(48)
    fun nickname(value: String) = value
        .replace(Regex("(?<!\\d)(?:\\d[ -]?){12,19}(?!\\d)"), "")
        .replace(Regex("[^\\p{L}\\p{M}\\p{N} .’'&-]"), "")
        .trim().replace(Regex(" +"), " ").take(48)
}
