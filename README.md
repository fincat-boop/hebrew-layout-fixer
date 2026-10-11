# מתקן שפה — Hebrew/English Layout Fixer for macOS

[English below](#english)

אפליקציה קטנה וחינמית לשורת התפריט במק, שמתקנת טקסט שנכתב בשפת מקלדת לא נכונה:
`akuo` ← "שלום", `יקךךם` ← "hello".

## מה היא עושה

**החלפה אוטומטית תוך כדי הקלדה.** אחרי 3 מילים רצופות שנכתבו בשפה הלא נכונה, כל הרצף
מוחלף לשפה הנכונה ושפת המקלדת מתחלפת, כך שממשיכים להקליד כרגיל.

- `cut bcsue t,` ← "בוא נבדוק את"
- `טםו גם מםא` ← "you do not"
- **Backspace מיד אחרי ההחלפה** מבטל אותה.
- מילה אחת או שתיים לא מוחלפות לבד. בשבילן יש קיצור מקלדת.
- כבוי אוטומטית בטרמינלים ובעורכי קוד.
- אפשר לכבות ולהדליק מתפריט האפליקציה.

**תיקון ידני: ⌘⇧H**
- בלי לסמן כלום: מתקן את כל הטקסט בשדה.
- עם טקסט מסומן: מתקן רק את מה שסומן.

## פרטיות

- הכול רץ על המחשב. אין חיבור לאינטרנט, אין שרת ואין איסוף נתונים.
- הזיהוי נעשה מול בודק האיות המובנה של macOS (עברית ואנגלית).
- שום טקסט לא נשמר. יומן האבחון (`~/Library/Logs/HebrewLayoutFixer.log`) רושם רק
  אירועים ומספרים, למשל "הוחלפו 3 מילים", בלי התוכן עצמו.

## הרשאות

האפליקציה צריכה הרשאת **נגישות** (הגדרות המערכת ← פרטיות ואבטחה ← נגישות) כדי לקרוא
את ההקלדה ולהחליף טקסט באפליקציות אחרות. בהפעלה הראשונה macOS יבקש לאשר.

## התקנה

### בנייה מהקוד (מומלץ)

צריך Xcode או Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/fincat-boop/hebrew-layout-fixer.git
cd hebrew-layout-fixer
./build_app.sh
```

גוררים את `HebrewLayoutFixer.app` לתיקיית Applications ומפעילים.

### הורדה מוכנה

אם יש קובץ מוכן בעמוד ה-Releases: האפליקציה לא חתומה אצל אפל, ולכן macOS יחסום
פתיחה רגילה. בפעם הראשונה: הגדרות המערכת ← פרטיות ואבטחה ← גוללים למטה ← "Open Anyway".

### אחרי עדכון

כל בנייה מחדש מקבלת חתימה חדשה, ו-macOS מבטל את הרשאת הנגישות. ברשימת הנגישות
מסירים את "מתקן שפה" (−) ומוסיפים מחדש (+).

## דרישות

macOS 12 ומעלה. מקלדות "Hebrew" ו-"ABC" (או U.S.) מוגדרות במערכת.

## התאמה

- קיצור המקלדת: `keyCode` ו-`modifiers` ב-`Sources/HebrewLayoutFixer/HotKeyManager.swift`.
- אפליקציות שבהן ההחלפה האוטומטית כבויה: `excludedBundleIDs` ב-`AutoSwitcher.swift`.
- רגישות הזיהוי: `runLength` ו-`minGibberish` ב-`AutoSwitcher.swift`.

## רישיון

MIT. חופשי לשימוש, לשינוי ולהפצה.

---

<a id="english"></a>

## English

A small, free macOS menu-bar app that fixes text typed in the wrong keyboard layout
(Hebrew ⇄ English, standard Israeli layout): `akuo` → "שלום", `יקךךם` → "hello".

**Automatic mode.** After three consecutive words typed in the wrong layout (each one a
real word once converted, at least two of them gibberish as typed), the whole run is
retyped in the right language and the keyboard layout switches. Backspace right after
undoes it. One or two words are never changed on their own. Off in terminals and
code editors. Toggle it from the menu.

**Manual fix: ⌘⇧H.** It converts the selected text, or the whole field when nothing is selected.

**Privacy.** Everything runs locally: no network access and no data collection. Detection uses
macOS's built-in spell checker. No typed text is stored or logged.

**Permissions.** Needs Accessibility access (System Settings → Privacy & Security →
Accessibility) to read keystrokes and replace text in other apps.

**Build.** Requires Xcode or the Command Line Tools.

```bash
./build_app.sh
```

Then move `HebrewLayoutFixer.app` to Applications. The app is ad-hoc signed (not notarized). For a
downloaded build, use System Settings → Privacy & Security → "Open Anyway". After each
rebuild, remove and re-add the app in the Accessibility list.

**Requirements.** macOS 12+, with the "Hebrew" and "ABC" (or U.S.) input sources enabled.

**License.** MIT.
