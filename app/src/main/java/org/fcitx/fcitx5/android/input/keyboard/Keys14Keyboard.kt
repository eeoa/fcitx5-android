/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * SPDX-FileCopyrightText: Copyright 2026 Fcitx5 for Android Contributors
 */
package org.fcitx.fcitx5.android.input.keyboard

import android.annotation.SuppressLint
import android.content.Context
import android.view.View
import androidx.annotation.Keep
import androidx.core.view.allViews
import org.fcitx.fcitx5.android.R
import org.fcitx.fcitx5.android.core.InputMethodEntry
import org.fcitx.fcitx5.android.data.prefs.AppPrefs
import org.fcitx.fcitx5.android.data.prefs.ManagedPreference
import org.fcitx.fcitx5.android.data.theme.Theme
import org.fcitx.fcitx5.android.input.picker.PickerWindow
import splitties.views.imageResource

/** Each key sends one spelling code; the Rime schema resolves all its letters. */
@SuppressLint("ViewConstructor")
class Keys14Keyboard(context: Context, theme: Theme) : BaseKeyboard(context, theme, Layout) {

    companion object {
        const val Name = "Keys14"
        const val SchemaName = "14键拼音"

        fun supports(ime: InputMethodEntry) =
            ime.uniqueName == "rime" && ime.subMode.name == SchemaName

        private fun letterKey(letters: String, alternate: String, width: Float = 0.2f) =
            KeyDef(
                KeyDef.Appearance.AltText(
                    displayText = letters.toCharArray().joinToString(" "),
                    altText = alternate,
                    textSize = 23f,
                    percentWidth = width
                ),
                setOf(
                    KeyDef.Behavior.Press(KeyAction.FcitxKeyAction(letters.first().lowercase())),
                    KeyDef.Behavior.Swipe(KeyAction.FcitxKeyAction(alternate))
                ),
                arrayOf(
                    KeyDef.Popup.AltPreview(letters, alternate),
                    KeyDef.Popup.Keyboard.Preset(alternate)
                )
            )

        val Layout: List<List<KeyDef>> = listOf(
            listOf(
                letterKey("QW", "1"),
                letterKey("ER", "2"),
                letterKey("TY", "3"),
                letterKey("UI", "4"),
                letterKey("OP", "5")
            ),
            listOf(
                letterKey("AS", "6"),
                letterKey("DF", "7"),
                letterKey("GH", "8"),
                letterKey("JK", "9"),
                letterKey("L", "0")
            ),
            listOf(
                KeyDef(
                    KeyDef.Appearance.Text(
                        "分词", 16f, percentWidth = 0.12f,
                        variant = KeyDef.Appearance.Variant.Alternative
                    ),
                    setOf(KeyDef.Behavior.Press(KeyAction.FcitxKeyAction("'"))),
                    arrayOf(KeyDef.Popup.Preview("'"))
                ),
                letterKey("ZX", "@"),
                letterKey("CV", "?"),
                letterKey("BN", "!"),
                letterKey("M", ".", 0.12f),
                BackspaceKey(0.16f)
            ),
            listOf(
                TextPickerSwitchKey("符", PickerWindow.Key.Symbol, 0.15f),
                CommaKey(0.1f, KeyDef.Appearance.Variant.Alternative),
                LanguageKey(),
                SpaceKey(),
                LayoutSwitchKey("123", NumberKeyboard.Name, 0.1f),
                ReturnKey()
            )
        )
    }

    private val space: TextKeyView by lazy { findViewById(R.id.button_space) }
    private val returnKey: ImageKeyView by lazy { findViewById(R.id.button_return) }
    private val lang: ImageKeyView by lazy { findViewById(R.id.button_lang) }
    private val showLangSwitchKey = AppPrefs.getInstance().keyboard.showLangSwitchKey

    @Keep
    private val showLangSwitchKeyListener = ManagedPreference.OnChangeListener<Boolean> { _, visible ->
        updateLangSwitchKey(visible)
    }

    init {
        updateLangSwitchKey(showLangSwitchKey.getValue())
        showLangSwitchKey.registerOnChangeListener(showLangSwitchKeyListener)
    }

    private fun updateLangSwitchKey(visible: Boolean) {
        lang.visibility = if (visible) View.VISIBLE else View.GONE
    }

    override fun onInputMethodUpdate(ime: InputMethodEntry) {
        space.mainText.text = SchemaName
    }

    override fun onReturnDrawableUpdate(returnDrawable: Int) {
        returnKey.img.imageResource = returnDrawable
    }

    override fun onPunctuationUpdate(mapping: Map<String, String>) {
        allViews.filterIsInstance<TextKeyView>().forEach {
            if (it is AltTextKeyView) {
                val def = it.def as KeyDef.Appearance.AltText
                it.altText.text = mapping.getOrDefault(def.altText, def.altText)
            } else {
                val def = it.def as KeyDef.Appearance.Text
                mapping[def.displayText]?.let { punctuation -> it.mainText.text = punctuation }
            }
        }
    }
}
