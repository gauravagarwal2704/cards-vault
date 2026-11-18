package com.cardswallet.cards_vault

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import kotlin.math.min
import kotlin.math.sqrt
import kotlin.math.roundToInt
import android.widget.RemoteViews
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject

/** Stores selected card previews in credential-protected app-private storage. */
open class CardWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { update(context, manager, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        update(context, manager, id)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val editor = preferences(context).edit()
        ids.forEach { editor.remove("widget_$it") }
        editor.apply()
    }

    override fun onRestored(context: Context, oldIds: IntArray, newIds: IntArray) {
        // Never transfer a preview or card identifier to a restored widget.
        onDeleted(context, oldIds)
        onDeleted(context, newIds)
        onUpdate(context, AppWidgetManager.getInstance(context), newIds)
    }

    companion object {
        private const val STORE = "card_widget_previews"
        private val safeId = Regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
        fun validCardId(id: String) = safeId.matches(id) && id != "." && id != ".." && id != "groups"
        private fun preferences(context: Context) = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
        private fun config(context: Context, id: Int): JSONObject = try {
            JSONObject(preferences(context).getString("widget_$id", "{}") ?: "{}")
        } catch (_: Exception) { JSONObject() }

        private fun activeIds(context: Context): List<Int> {
            val manager = AppWidgetManager.getInstance(context)
            return (manager.getAppWidgetIds(ComponentName(context, CardWidgetProvider::class.java)).asList() +
                manager.getAppWidgetIds(ComponentName(context, VerticalCardWidgetProvider::class.java)).asList() +
                manager.getAppWidgetIds(ComponentName(context, CompactCardWidgetProvider::class.java)).asList())
                .distinct()
        }

        fun hasWidgets(context: Context) = activeIds(context).isNotEmpty()

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            activeIds(context).forEach { update(context, manager, it) }
        }

        private fun appLogo(context: Context): Int {
            val icon = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getString("flutter.appearance_app_icon", "three_d")
            return when (icon) {
                "purple" -> R.mipmap.ic_launcher_purple
                "multicolor" -> R.mipmap.ic_launcher_multicolor
                "ocean" -> R.mipmap.ic_launcher_ocean
                "emerald" -> R.mipmap.ic_launcher_emerald
                "sunset" -> R.mipmap.ic_launcher_sunset
                "red" -> R.mipmap.ic_launcher_red
                else -> R.mipmap.ic_launcher_three_d
            }
        }

        private fun selectedIds(config: JSONObject): List<String> {
            val ids = config.optJSONArray("ids") ?: JSONArray()
            return (0 until minOf(ids.length(), 4)).map { ids.optString(it) }.filter(::validCardId).distinct()
        }
        fun previewCardIds(context: Context): List<String> = activeIds(context)
            .flatMap { id -> selectedIds(config(context, id)) }.distinct()

        private fun requireWidget(context: Context, id: Int) {
            require(activeIds(context).contains(id)) { "Widget unavailable" }
        }

        fun configuration(context: Context, id: Int): Map<String, Any> {
            requireWidget(context, id)
            return mapOf("ids" to selectedIds(config(context, id)))
        }

        fun save(context: Context, id: Int, ids: List<String>) {
            requireWidget(context, id)
            require(ids.size <= 4 && ids.distinct().size == ids.size && ids.all(::validCardId))
            // Discard stale previews until the selected cards are freshly rendered.
            val config = JSONObject().put("ids", JSONArray(ids))
            preferences(context).edit().putString("widget_$id", config.toString()).apply()
            update(context, AppWidgetManager.getInstance(context), id)
        }

        private val networks = setOf("Visa", "Mastercard", "American Express", "Discover", "JCB",
            "Diners Club", "UnionPay", "RuPay", "Google Pay", "Maestro", "Unknown")


        fun sync(context: Context, cards: List<Map<*, *>>) {
            val byId = cards.associateBy { it["id"] as? String }
            val editor = preferences(context).edit()
            activeIds(context).forEach { id ->
                val config = config(context, id)
                val ids = selectedIds(config).filter { byId.containsKey(it) }
                val previews = JSONArray()
                ids.forEach { cardId ->
                    val card = byId.getValue(cardId)
                    // ID-only snapshots must never be treated as full previews.
                    if (card["holder"] !is String || card["bank"] !is String) {
                        previews.put(JSONObject())
                    } else {
                        val lastFour = (card["lastFour"] as? String).orEmpty()
                            .takeIf { Regex("^[0-9]{4}$").matches(it) }.orEmpty()
                        previews.put(JSONObject()
                            .put("bank", (card["bank"] as String).take(32))
                            .put("lastFour", lastFour)
                            .put("holder", CardWidgetPreviewPolicy.name(card["holder"] as String))
                            .put("nickname", CardWidgetPreviewPolicy.nickname((card["nickname"] as? String).orEmpty()))
                            .put("network", (card["network"] as? String)?.takeIf { it in networks } ?: "Unknown")
                            .put("category", if (card["category"] == "Debit") "Debit" else "Credit")
                            .put("color", (card["color"] as? Number)?.toInt() ?: 0xFF344D8C.toInt())
                            .put("background", encodeImage(card["background"]))
                            .put("logo", encodeImage(card["logo"]))
                            .put("bankLogo", encodeImage(card["bankLogo"]))
                            .put("foreground", (card["foreground"] as? Number)?.toInt() ?: 0xFFF7F4ED.toInt()))
                    }
                }
                config.put("ids", JSONArray(ids)).put("previews", previews)
                editor.putString("widget_$id", config.toString())
            }
            editor.apply()
            activeIds(context).forEach { update(context, AppWidgetManager.getInstance(context), it) }
        }

        fun clearPreviews(context: Context) {
            val editor = preferences(context).edit()
            activeIds(context).forEach { id ->
                val config = config(context, id).put("previews", JSONArray())
                editor.putString("widget_$id", config.toString())
            }
            editor.apply()
            activeIds(context).forEach { update(context, AppWidgetManager.getInstance(context), it) }
        }

        private fun encodeImage(value: Any?): String {
            val bytes = value as? ByteArray ?: return ""
            if (bytes.size > 131072 || bytes.isEmpty()) return ""
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            if (bounds.outWidth !in 1..512 || bounds.outHeight !in 1..512 ||
                bounds.outWidth * bounds.outHeight > 200000) return ""
            return Base64.encodeToString(bytes, Base64.NO_WRAP)
        }

        private fun decodeImage(value: String): Bitmap? = try {
            if (value.length > 175000) null else {
                val bytes = Base64.decode(value, Base64.NO_WRAP)
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                if (bounds.outWidth !in 1..512 || bounds.outHeight !in 1..512 ||
                    bounds.outWidth * bounds.outHeight > 200000) null
                else BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            }
        } catch (_: Exception) { null }

        private fun launch(context: Context, host: String, id: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.Builder().scheme("cardvault").authority(host).appendPath(id).build()
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            // URI is part of PendingIntent identity: different cards never overwrite each other.
            return PendingIntent.getActivity(context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun layout(context: Context, id: Int, width: Float, height: Float, pixelBudget: Float): RemoteViews {
            val config = config(context, id)
            val ids = selectedIds(config)
            val previews = config.optJSONArray("previews") ?: JSONArray()
            val fontScale = context.resources.configuration.fontScale
            val providerName = AppWidgetManager.getInstance(context).getAppWidgetInfo(id)
                ?.provider?.className
            val vertical = providerName == VerticalCardWidgetProvider::class.java.name
            val compactSquare = providerName == CompactCardWidgetProvider::class.java.name &&
                height >= width * .75f && height <= width * 1.2f
            val plan = CardWidgetGeometry.plan(width, height, ids.size, vertical, compactSquare)
            val resource = when {
                compactSquare -> R.layout.card_widget_compact_square
                plan.count == 1 -> R.layout.card_widget_single
                plan.rows == 1 -> R.layout.card_widget_wide
                plan.columns == 1 -> R.layout.card_widget_tall
                else -> R.layout.card_widget_square
            }
            val views = RemoteViews(context.packageName, resource)
            val count = minOf(ids.size, plan.count)
            val slots = intArrayOf(R.id.widget_card_0, R.id.widget_card_1, R.id.widget_card_2, R.id.widget_card_3)
            views.setTextViewText(R.id.widget_title, "Card Vault")
            views.setImageViewResource(R.id.widget_app_logo, appLogo(context))
            views.setViewVisibility(R.id.widget_empty, if (count == 0) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_cards, if (count == 0) View.GONE else View.VISIBLE)
            views.setOnClickPendingIntent(R.id.widget_header, launch(context, "widgets", id.toString()))
            views.setOnClickPendingIntent(R.id.widget_settings, launch(context, "widgets", id.toString()))
            views.setOnClickPendingIntent(R.id.widget_empty, launch(context, "widgets", id.toString()))
            val area = (plan.cardWidth * plan.cardHeight * plan.count).coerceAtLeast(1f)
            val density = min(context.resources.displayMetrics.density, 3f)
            val renderScale = min(density, sqrt(pixelBudget / area))
            val bitmapWidth = (plan.cardWidth * renderScale).roundToInt().coerceIn(24, 960)
            val palette = intArrayOf(0xFF344D8C.toInt(), 0xFF176B68.toInt(), 0xFF6F458E.toInt(), 0xFF6B513A.toInt())
            slots.forEachIndexed { index, slot ->
                val visibility = when {
                    index < count -> View.VISIBLE
                    else -> View.GONE
                }
                views.setViewVisibility(slot, visibility)
                if (index < count) {
                    val preview = previews.optJSONObject(index)
                    val detailed = preview?.has("bank") == true
                    val face = if (detailed) CardWidgetRenderer.Face(
                        preview.optString("bank", "CardVault"), preview.optString("holder").ifEmpty { "CARDHOLDER" },
                        preview.optString("lastFour"), preview.optString("network", "Unknown"),
                        preview.optString("category", "Credit"), preview.optInt("color", palette[index]),
                        background = decodeImage(preview.optString("background")),
                        logo = decodeImage(preview.optString("logo")),
                        foreground = preview.optInt("foreground", 0xFFF7F4ED.toInt()),
                        bankLogo = decodeImage(preview.optString("bankLogo")),
                        nickname = preview.optString("nickname"))
                    else CardWidgetRenderer.Face("CARDVAULT", "Card ${index + 1}", "", "", "", palette[index], isPrivate = true)
                    val cardBitmap = CardWidgetRenderer.bitmap(face, bitmapWidth, fontScale,
                        compact = plan.cardWidth < 190f)
                    // Intrinsic size packs rows tightly on Android 8–11 as well.
                    cardBitmap.density = CardWidgetGeometry.bitmapDensity(cardBitmap.width, plan.cardWidth)
                    views.setImageViewBitmap(slot, cardBitmap)
                    face.background?.recycle()
                    face.logo?.recycle()
                    face.bankLogo?.recycle()
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        views.setViewLayoutWidth(slot, plan.cardWidth, android.util.TypedValue.COMPLEX_UNIT_DIP)
                        views.setViewLayoutHeight(slot, plan.cardHeight, android.util.TypedValue.COMPLEX_UNIT_DIP)
                    }
                    val label = if (detailed) listOf(face.bank, face.nickname, face.category, face.network,
                        "ending in ${face.lastFour}", face.holder).joinToString(", ")
                        else "Card ${index + 1}, private preview, tap to open"
                    views.setContentDescription(slot, label)
                    views.setOnClickPendingIntent(slot, launch(context, "cards", ids[index]))
                }
            }
            return views
        }

        fun update(context: Context, manager: AppWidgetManager, id: Int) {
            val options = manager.getAppWidgetOptions(id)
            val portrait = SizeF(
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180).coerceAtLeast(80).toFloat(),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 160).coerceAtLeast(90).toFloat())
            val landscape = SizeF(
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 260).coerceAtLeast(80).toFloat(),
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 140).coerceAtLeast(90).toFloat())
            val supplied = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                @Suppress("DEPRECATION")
                options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                    ?.filter { it.width.isFinite() && it.height.isFinite() && it.width > 0 && it.height > 0 }
                    ?.distinct()?.take(4)
            } else null
            val sizes = if (!supplied.isNullOrEmpty()) supplied else listOf(portrait, landscape).distinct()
            val density = context.resources.displayMetrics.density
            // Android limits ALL bitmap allocations in one RemoteViews update.
            // Budget across every orientation/size; never rasterize full-size photos.
            val pixelBudget = (sizes.minOf { it.width * it.height } * density * density * .9f)
                .coerceAtMost(2_000_000f) / sizes.size
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                manager.updateAppWidget(id, RemoteViews(sizes.associateWith {
                    layout(context, id, it.width, it.height, pixelBudget)
                }))
            } else {
                manager.updateAppWidget(id, RemoteViews(
                    layout(context, id, landscape.width, landscape.height, pixelBudget),
                    layout(context, id, portrait.width, portrait.height, pixelBudget)))
            }
        }
    }
}
