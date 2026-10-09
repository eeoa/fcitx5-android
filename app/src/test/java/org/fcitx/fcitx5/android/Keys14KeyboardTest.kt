/*
 * SPDX-License-Identifier: LGPL-2.1-or-later
 * SPDX-FileCopyrightText: Copyright 2026 Fcitx5 for Android Contributors
 */
package org.fcitx.fcitx5.android

import org.fcitx.fcitx5.android.core.InputMethodEntry
import org.fcitx.fcitx5.android.core.InputMethodSubMode
import org.fcitx.fcitx5.android.input.keyboard.KeyAction
import org.fcitx.fcitx5.android.input.keyboard.KeyDef
import org.fcitx.fcitx5.android.input.keyboard.Keys14Keyboard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class Keys14KeyboardTest {
    @Test
    fun allLettersHaveExactlyOneKeyAndMatchTheDecoder() {
        val keys = Keys14Keyboard.Layout.take(3).flatten()
            .filter { it.appearance is KeyDef.Appearance.AltText }
        assertEquals(14, keys.size)
        val letters = keys.flatMap {
            (it.appearance as KeyDef.Appearance.AltText).displayText.filter(Char::isLetter).toList()
        }
        assertEquals(('A'..'Z').toList(), letters.sorted())

        // Changing the UI without changing the spelling prism must fail a check.
        val schema = File("../plugin/rime/src/main/cpp/keys14_pinyin.schema.yaml").readText()
        val rule = Regex("xlit/([a-z]+)/([a-z]+)/").find(schema)!!
        val alphabet = rule.groupValues[1]
        val codes = rule.groupValues[2]
        assertEquals(26, alphabet.length)
        assertEquals(alphabet.length, codes.length)
        keys.forEach { key ->
            val appearance = key.appearance as KeyDef.Appearance.AltText
            val press = key.behaviors.filterIsInstance<KeyDef.Behavior.Press>().single()
            val action = press.action as KeyAction.FcitxKeyAction
            assertEquals(1, action.act.length)
            appearance.displayText.filter(Char::isLetter).forEach {
                assertEquals(codes[alphabet.indexOf(it.lowercaseChar())], action.act.single())
            }
        }
        Keys14Keyboard.Layout.take(3).forEach { row ->
            assertEquals(1f, row.sumOf { it.appearance.percentWidth.toDouble() }.toFloat(), 0.0001f)
        }
    }

    @Test
    fun pairedLayoutOnlyAppearsWithItsMatchingDecoder() {
        val rime = InputMethodEntry("rime", "Rime", "", "", "", "zh", "rime", true,
            InputMethodSubMode(Keys14Keyboard.SchemaName, "1", "fcitx-rime"))
        assertTrue(Keys14Keyboard.supports(rime))
        assertFalse(Keys14Keyboard.supports(rime.copy(uniqueName = "pinyin")))
        assertFalse(Keys14Keyboard.supports(rime.copy(subMode = InputMethodSubMode("Latin Mode", "A", ""))))
        assertFalse(Keys14Keyboard.supports(rime.copy(subMode = InputMethodSubMode("朙月拼音", "朙", ""))))
    }
}
