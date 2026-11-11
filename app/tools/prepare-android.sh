#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

ORG="gg.gridandglory"
APP_ID="gg.gridandglory.app"
PROJECT="grid_and_glory"

if ! command -v flutter >/dev/null 2>&1; then
  echo "error: flutter is not on PATH. Install the SDK first: https://docs.flutter.dev/get-started/install" >&2
  exit 1
fi

if [ ! -d android ]; then
  echo "==> generating android/ (flutter create)"
  cp pubspec.yaml /tmp/gg_pubspec.yaml
  cp analysis_options.yaml /tmp/gg_analysis.yaml
  flutter create --platforms=android --org "$ORG" --project-name "$PROJECT" .
  rm -f test/widget_test.dart
  rmdir test 2>/dev/null || true
  cp /tmp/gg_pubspec.yaml pubspec.yaml
  cp /tmp/gg_analysis.yaml analysis_options.yaml
fi

echo "==> patching manifest, applicationId, app name, signing, MainActivity package"
python3 - "$APP_DIR" "$APP_ID" <<'PY'
import pathlib
import re
import sys

app_dir = pathlib.Path(sys.argv[1])
app_id = sys.argv[2]

manifest = app_dir / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
text = manifest.read_text()
if "android.permission.INTERNET" not in text:
    text = text.replace(
        "<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n\n    <application',
        1,
    )

if "@string/app_name" not in text:
    text = re.sub(r'android:label="[^"]*"', 'android:label="@string/app_name"', text, count=1)
manifest.write_text(text)

res_dir = app_dir / "android" / "app" / "src" / "main" / "res"
for locale, name in [("values", "Grid &amp; Glory"), ("values-ar", "التحدي الكروي")]:
    folder = res_dir / locale
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "strings.xml").write_text(
        f'<?xml version="1.0" encoding="utf-8"?>\n'
        f'<resources>\n    <string name="app_name">{name}</string>\n</resources>\n',
        encoding="utf-8",
    )

# Branded Android 12+ launch screen. This is generated on every clean CI build.
drawable_dir = res_dir / "drawable"
drawable_dir.mkdir(parents=True, exist_ok=True)
(drawable_dir / "gg_splash_icon.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" '
    'android:width="108dp" android:height="108dp" android:viewportWidth="108" '
    'android:viewportHeight="108">\n'
    '  <path android:fillColor="#FFC24B" android:pathData="M54,5 L94,20 L88,63 '
    'Q82,88 54,102 Q26,88 20,63 L14,20 Z"/>\n'
    '  <path android:fillColor="#10233A" android:pathData="M54,15 L83,26 L79,61 '
    'Q74,80 54,91 Q34,80 29,61 L25,26 Z"/>\n'
    '  <path android:strokeColor="#75D6B0" android:strokeWidth="3" '
    'android:fillColor="#00000000" android:pathData="M38,36 L70,36 L70,68 '
    'L38,68 Z M54,36 L54,68 M38,52 L70,52"/>\n'
    '  <path android:fillColor="#FFC24B" android:pathData="M54,43 '
    'A9,9 0,1 0,54.1 43 Z"/>\n'
    '</vector>\n',
    encoding="utf-8",
)
# Replace Flutter's default launcher mark with the same Grid & Glory shield.
launcher_vector = (
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" '
    'android:width="108dp" android:height="108dp" android:viewportWidth="108" '
    'android:viewportHeight="108">\n'
    '  <path android:fillColor="#FFC24B" android:pathData="M54,5 L94,20 L88,63 '
    'Q82,88 54,102 Q26,88 20,63 L14,20 Z"/>\n'
    '  <path android:fillColor="#10233A" android:pathData="M54,15 L83,26 L79,61 '
    'Q74,80 54,91 Q34,80 29,61 L25,26 Z"/>\n'
    '  <path android:strokeColor="#75D6B0" android:strokeWidth="3" '
    'android:fillColor="#00000000" android:pathData="M38,36 L70,36 L70,68 '
    'L38,68 Z M54,36 L54,68 M38,52 L70,52"/>\n'
    '  <path android:fillColor="#FFC24B" android:pathData="M54,43 '
    'A9,9 0,1 0,54.1 43 Z"/>\n'
    '</vector>\n'
)
mipmap = res_dir / "mipmap-anydpi"
mipmap.mkdir(parents=True, exist_ok=True)
(mipmap / "ic_launcher.xml").write_text(launcher_vector, encoding="utf-8")
mipmap_v26 = res_dir / "mipmap-anydpi-v26"
mipmap_v26.mkdir(parents=True, exist_ok=True)
(mipmap_v26 / "ic_launcher.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '  <background android:drawable="@color/gg_icon_background"/>\n'
    '  <foreground android:drawable="@drawable/gg_splash_icon"/>\n'
    '</adaptive-icon>\n',
    encoding="utf-8",
)
colors = res_dir / "values" / "colors.xml"
if colors.exists():
    color_xml = colors.read_text(encoding="utf-8")
    if "gg_icon_background" not in color_xml:
        color_xml = color_xml.replace(
            "</resources>",
            '    <color name="gg_icon_background">#10233A</color>\n</resources>',
        )
else:
    color_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources><color name="gg_icon_background">#10233A</color></resources>\n'
    )
colors.write_text(color_xml, encoding="utf-8")

v31 = res_dir / "values-v31"
v31.mkdir(parents=True, exist_ok=True)
(v31 / "styles.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources>\n'
    '  <style name="LaunchTheme" parent="Theme.SplashScreen">\n'
    '    <item name="windowSplashScreenBackground">#0B1220</item>\n'
    '    <item name="windowSplashScreenAnimatedIcon">@drawable/gg_splash_icon</item>\n'
    '    <item name="windowSplashScreenIconBackgroundColor">#172B40</item>\n'
    '    <item name="postSplashScreenTheme">@style/NormalTheme</item>\n'
    '  </style>\n'
    '  <style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">\n'
    '    <item name="android:windowBackground">?android:colorBackground</item>\n'
    '  </style>\n'
    '</resources>\n',
    encoding="utf-8",
)

main_dir = app_dir / "android" / "app" / "src" / "main"
for src in list(main_dir.rglob("MainActivity.kt")) + list(main_dir.rglob("MainActivity.java")):
    rel = src.relative_to(main_dir)
    lang_root = main_dir / rel.parts[0]
    dest = lang_root.joinpath(*app_id.split(".")) / src.name
    source = src.read_text()
    patched = re.sub(r"^package\s+[\w.]+", f"package {app_id}", source, count=1, flags=re.M)
    if dest != src:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(patched)
        src.unlink()
        parent = src.parent
        while parent != lang_root and parent.exists() and not any(parent.iterdir()):
            parent.rmdir()
            parent = parent.parent
    else:
        src.write_text(patched)

for gradle in list(app_dir.glob("android/app/build.gradle*")):
    s = gradle.read_text()
    s = re.sub(r'namespace\s*[= ]\s*"[^"]*"', f'namespace = "{app_id}"', s)
    s = re.sub(r'applicationId\s*[= ]\s*"[^"]*"', f'applicationId = "{app_id}"', s)

    if "// gg:signing" not in s:
        s = "import java.util.Properties\nimport java.io.FileInputStream\n\n" + s

        prologue = (
            "// gg:signing\n"
            "val keystoreProperties = Properties()\n"
            "val keystorePropertiesFile = rootProject.file(\"key.properties\")\n"
            "val hasReleaseKey = keystorePropertiesFile.exists()\n"
            "if (hasReleaseKey) {\n"
            "    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n"
            "}\n\n"
            "android {\n"
            "    signingConfigs {\n"
            "        create(\"release\") {\n"
            "            keyAlias = keystoreProperties[\"keyAlias\"] as String?\n"
            "            keyPassword = keystoreProperties[\"keyPassword\"] as String?\n"
            "            storeFile = (keystoreProperties[\"storeFile\"] as String?)?.let { file(it) }\n"
            "            storePassword = keystoreProperties[\"storePassword\"] as String?\n"
            "        }\n"
            "    }\n"
        )
        s = s.replace("android {", prologue, 1)

        s = s.replace(
            "signingConfig = signingConfigs.getByName(\"debug\")",
            "signingConfig = if (hasReleaseKey) signingConfigs.getByName(\"release\") "
            "else signingConfigs.getByName(\"debug\")",
        )

    # AndroidX supplies the compatibility SplashScreen theme and its attributes.
    dependency = 'implementation("androidx.core:core-splashscreen:1.0.1")' if gradle.suffix == ".kts" else "implementation 'androidx.core:core-splashscreen:1.0.1'"
    if "core-splashscreen" not in s:
        if re.search(r"(?m)^dependencies\s*\{", s):
            s = re.sub(r"(?m)^dependencies\s*\{", lambda m: m.group(0) + "\n    " + dependency, s, count=1)
        else:
            s += "\n\ndependencies {\n    " + dependency + "\n}\n"

    gradle.write_text(s)

debug_manifest = app_dir / "android" / "app" / "src" / "debug" / "AndroidManifest.xml"
debug_manifest.parent.mkdir(parents=True, exist_ok=True)
if not debug_manifest.exists() or "usesCleartextTraffic" not in debug_manifest.read_text():
    debug_manifest.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <uses-permission android:name="android.permission.INTERNET"/>\n'
        '    <application android:usesCleartextTraffic="true" />\n'
        '</manifest>\n'
    )

key_props = app_dir / "android" / "key.properties"
print(f"    applicationId -> {app_id}")
print(f"    release signing -> {'key.properties found' if key_props.exists() else 'no key (debug signing)'}")
PY

if ! grep -rq "^package gg.gridandglory.app" android/app/src/main/kotlin android/app/src/main/java 2>/dev/null; then
  echo "error: MainActivity package does not match applicationId" >&2
  exit 1
fi

echo "==> done. Next:"
echo "    cd app && flutter pub get && flutter gen-l10n"
echo "    flutter build apk --release --dart-define=WS_URL=wss://<host>/ws"
