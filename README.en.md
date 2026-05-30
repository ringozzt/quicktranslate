# QuickTranslate

**English** · [简体中文](./README.md)

> A dead-simple macOS pop-up translator: select text anywhere, hit **⌥D**, and get the translation right next to your cursor — powered by **macOS's built-in translation engine**. **No API keys, no cost, no account, no network login.**

<p align="center">
  <img src="./assets/demo.gif" width="720" alt="QuickTranslate demo">
</p>

Inspired by [Bob](https://bobtranslate.com/). Bob's "system translation" actually works by calling macOS's native **Translate Text** action through a **Shortcut**. QuickTranslate distills that idea into a tiny menu-bar app — under 300 lines of Swift.

---

## ✨ Features

- **⌥D selection translation** — select text in any app, press `⌥D`, the translation pops up by your cursor
- **Auto direction** — English → Chinese, Chinese → English (switched automatically based on what you selected)
- **Native engine** — uses the macOS Translation engine; no third-party API, no cost
- **Click the result to copy**, press `Esc` to dismiss
- **Lives in the menu bar**, no Dock icon, negligible footprint
- Bonus: "Translate clipboard contents" from the menu

## 📦 Requirements

- macOS 12.3 or later (relies on Shortcuts + system translation)
- A Shortcut that invokes system translation (see [Setting up the Shortcut](#-setting-up-the-shortcut))
- Xcode command-line tools for the first build (`xcrun swiftc`)

---

## 🚀 Install

### One-liner

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ringozzt/quicktranslate/main/install.sh)"
```

This clones the repo to `~/quicktranslate`, builds the app, and launches it.

### Manual

```bash
git clone https://github.com/ringozzt/quicktranslate.git
cd quicktranslate
./build.sh
open build/QuickTranslate.app
```

A **译** icon appears in the menu bar once it's running.

### Grant Accessibility permission (one-time)

Simulating `⌘C` to grab the selected text requires Accessibility permission:

1. On first launch you'll be prompted — click "Open System Settings" (or use menu bar **译 → Accessibility settings…**)
2. **System Settings › Privacy & Security › Accessibility** → enable **QuickTranslate**
3. Quit and **relaunch** the app (the permission takes effect after a restart)

---

## 🔧 Setting up the Shortcut

QuickTranslate calls system translation through a Shortcut. By default it runs a Shortcut named `Bob.Translate.v2` (if you've ever used Bob's "system translation", it was installed automatically — it just works).

**If you don't have Bob**, create a Shortcut with the same name yourself (open the Shortcuts app, new shortcut, add these actions in order):

1. **Receive** `Text` input (from Shortcut Input)
2. **Get Dictionary** from `Shortcut Input`
3. Get value for `detectFrom` → set variable **from**
4. Get value for `detectTo` → set variable **to**
5. Get value for `text` → set variable **text**
6. **Translate Text**: translate `text` from `from` to `to`
7. **Stop and output** `Translated Text`

> You may name it anything and update the `kShortcutName` constant in `src/main.swift`.

Verify the Shortcut works:

```bash
echo '{"text":"hello world","detectFrom":"","detectTo":"zh_CN"}' | shortcuts run "Bob.Translate.v2"
# Expected: 你好，世界
```

> ⚠️ **Use language identifiers like `zh_CN` / `en_US`** (the `lang_REGION` form), not `zh-Hans` / `en`, otherwise macOS reports "translation not supported". Hard-won lesson.

---

## ⚙️ How it works

```
Press ⌥D
  → simulate ⌘C to copy the selected text
  → read the clipboard, detect direction (CJK ratio)
  → build {"text", "detectFrom":"", "detectTo":"zh_CN"|"en_US"}
  → pipe it to `shortcuts run` (= the native Translate Text action)
  → show the result in a panel next to the cursor
```

The global hotkey uses Carbon `RegisterEventHotKey`, the pop-up is a borderless `NSPanel`, and the whole thing is an `LSUIElement` menu-bar app.

## 🛠 Customize

Edit the constants at the top of `src/main.swift`, then re-run `./build.sh`:

| Constant | Purpose | Default |
|----------|---------|---------|
| `kShortcutName` | Shortcut to invoke | `Bob.Translate.v2` |
| `kHotKeyCode` | Hotkey key | `kVK_ANSI_D` (D) |
| `kHotKeyMods` | Modifier | `optionKey` (⌥) |

Direction logic lives in `nativeTranslate()` and `isMostlyCJK()` — extend there for more languages.

## ❓ Troubleshooting

- **⌥D does nothing / no text captured**: make sure Accessibility permission is on and you've relaunched the app.
- **"Translation not supported"**: use `zh_CN`/`en_US` identifiers; or the language pair isn't ready yet — run the **Translate Text** action once in the Shortcuts app to initialize it.
- **⌥D clashes with another app**: change `kHotKeyCode` / `kHotKeyMods` and rebuild.

## 🙏 Credits

- [Bob](https://bobtranslate.com/) — the inspiration and reference for the Shortcut-based system-translation approach

## 📄 License

[MIT](./LICENSE)
