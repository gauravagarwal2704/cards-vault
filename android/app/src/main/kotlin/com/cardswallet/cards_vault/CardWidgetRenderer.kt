package com.cardswallet.cards_vault

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import kotlin.math.min
import kotlin.math.roundToInt

/** Draws only selected, bounded fields over the app's isolated background artwork. */
object CardWidgetRenderer {
    data class Face(val bank: String, val holder: String, val lastFour: String,
                    val network: String, val category: String, val color: Int,
                    val isPrivate: Boolean = false, val background: Bitmap? = null,
                    val logo: Bitmap? = null, val foreground: Int = 0xFFF7F4ED.toInt(),
                    val bankLogo: Bitmap? = null, val nickname: String = "")

    fun bitmap(face: Face, pixelWidth: Int, fontScale: Float = 1f, compact: Boolean = false): Bitmap {
        val width = pixelWidth.coerceIn(24, 960)
        val height = (width / CardWidgetGeometry.RATIO).roundToInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val h = 340f / CardWidgetGeometry.RATIO
        canvas.scale(width / 340f, height / h)
        val bounds = RectF(0f, 0f, 340f, h)
        canvas.clipPath(Path().apply { addRoundRect(bounds, 16f, 16f, Path.Direction.CW) })
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        if (!face.isPrivate && face.background != null) {
            canvas.drawBitmap(face.background, null, bounds, paint)
        } else {
            // Private previews reveal neither the saved artwork nor the bank.
            paint.shader = LinearGradient(0f, 0f, 340f, h, face.color,
                Color.rgb(18, 25, 43), Shader.TileMode.CLAMP)
            canvas.drawRect(bounds, paint)
            paint.shader = null
        }
        val foreground = if (face.isPrivate) Color.WHITE else face.foreground
        val scale = fontScale.coerceIn(1f, 1.2f)
        fun text(value: String, x: Float, y: Float, size: Float, maxWidth: Float, bold: Boolean = false) {
            val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = foreground
                textSize = size * scale
                typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
            }
            canvas.drawText(TextUtils.ellipsize(value, textPaint, maxWidth,
                TextUtils.TruncateAt.END).toString(), x, y, textPaint)
        }
        val nickname = face.nickname.takeIf { it.isNotEmpty() && !face.isPrivate }
        val topRight = if (nickname == null) 320f else 173f
        if (!face.isPrivate && face.bankLogo != null) {
            val bankLogo = face.bankLogo
            val s = min((topRight - 20f) / bankLogo.width, 41f / bankLogo.height)
            val logoWidth = bankLogo.width * s
            val logoHeight = bankLogo.height * s
            canvas.drawBitmap(bankLogo, null, RectF(20f, 17f, 20f + logoWidth,
                17f + logoHeight), paint)
        } else {
            text(face.bank, 20f, 45f, if (compact) 27f else 25f,
                topRight - 20f, bold = true)
        }
        if (nickname != null) {
            val nicknamePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = foreground
                textSize = (if (compact) 19f else 18f) * scale
                typeface = Typeface.create("sans-serif", Typeface.BOLD)
            }
            val label = TextUtils.ellipsize(nickname, nicknamePaint, 139f,
                TextUtils.TruncateAt.END).toString()
            canvas.drawText(label, 320f - nicknamePaint.measureText(label), 43f,
                nicknamePaint)
        }
        val suffix = face.lastFour.takeIf { Regex("^[0-9]{4}$").matches(it) } ?: "••••"
        val numberPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = foreground
            textSize = (if (compact) 32f else 30f) * scale
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        }
        // Measure the dot group, then use one small optical gap before the suffix.
        val dots = "••••"
        canvas.drawText(dots, 20f, 135f, numberPaint)
        canvas.drawText(suffix, 20f + numberPaint.measureText(dots) + 8f, 135f, numberPaint)
        text(face.holder, 20f, 189f, if (compact) 24f else 22f,
            if (face.logo != null && !face.isPrivate) 210f else 300f, bold = true)
        if (!face.isPrivate && face.logo != null) {
            val logo = face.logo
            val s = min(72f / logo.width, 40f / logo.height)
            val logoWidth = logo.width * s
            val logoHeight = logo.height * s
            canvas.drawBitmap(logo, null, RectF(320f - logoWidth, 194f - logoHeight,
                320f, 194f), paint)
        }
        return bitmap
    }
}
