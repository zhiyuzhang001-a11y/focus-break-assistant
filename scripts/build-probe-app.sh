#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
bundle_name="Focus Break Assistant.app"
info_plist="$project_root/Support/FocusBreakProbe-Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
architecture=$(uname -m)
package_dir="$project_root/.build/package"
bundle_path="$package_dir/$bundle_name"
contents_path="$bundle_path/Contents"
resource_bundle_name="FocusBreakAssistant_FocusBreakProbe.bundle"
iconset_path="$package_dir/FocusBreakAssistant.iconset"
dmg_root="$package_dir/dmg-root"
dmg_path="$package_dir/Focus-Break-Assistant-$version-macos-$architecture.dmg"
legacy_bundle_path="$project_root/.build/FocusBreakProbe.app"
legacy_named_bundle_path="$project_root/.build/$bundle_name"
install_directory="/Applications"
install_path="$install_directory/$bundle_name"
staging_path="$install_directory/.FocusBreakAssistant-install-$$"
backup_path="$install_directory/.FocusBreakAssistant-previous-$$"
install_committed=false

cd "$project_root"
swift build -c release

rm -rf "$bundle_path" "$iconset_path" "$dmg_root"
rm -f "$dmg_path"
mkdir -p "$contents_path/MacOS" "$contents_path/Resources" "$iconset_path" "$dmg_root"
cp "$project_root/.build/release/focus-break-probe" "$contents_path/MacOS/focus-break-probe"
chmod 755 "$contents_path/MacOS/focus-break-probe"
cp -R "$project_root/.build/release/$resource_bundle_name" "$contents_path/Resources/$resource_bundle_name"
cp "$info_plist" "$contents_path/Info.plist"

for icon_size in 16 32 128 256 512; do
    retina_size=$((icon_size * 2))
    sips -z "$icon_size" "$icon_size" "$project_root/Support/FocusBreakAssistant-icon-source.png" \
        --out "$iconset_path/icon_${icon_size}x${icon_size}.png" >/dev/null
    sips -z "$retina_size" "$retina_size" "$project_root/Support/FocusBreakAssistant-icon-source.png" \
        --out "$iconset_path/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset_path" -o "$contents_path/Resources/FocusBreakAssistant.icns"

plutil -lint "$contents_path/Info.plist"
/usr/bin/codesign --force --sign - "$bundle_path"
/usr/bin/codesign --verify --deep --strict "$bundle_path"
"$contents_path/MacOS/focus-break-probe" --snapshot-no-accessibility >/dev/null

# Create a standard drag-to-Applications disk image. Only the DMG remains in
# the build directory; staging Apps are removed after installation so
# Spotlight sees a single copy.
/usr/bin/ditto "$bundle_path" "$dmg_root/$bundle_name"
ln -s /Applications "$dmg_root/Applications"
hdiutil create -quiet -fs HFS+ -format UDBZ -volname "Focus Break Assistant" \
    -srcfolder "$dmg_root" "$dmg_path"
hdiutil verify "$dmg_path" >/dev/null

# Install from a fully-built, signed staging bundle. Moving the current copy
# aside only after staging succeeds keeps Applications to one canonical App.
rm -rf "$staging_path" "$backup_path"
trap 'if [[ "$install_committed" != true && -d "$backup_path" ]]; then rm -rf "$install_path"; mv "$backup_path" "$install_path"; fi; rm -rf "$staging_path"' EXIT
/usr/bin/ditto "$bundle_path" "$staging_path"
/usr/bin/codesign --verify --deep --strict "$staging_path"

if [[ -d "$install_path" ]]; then
    mv "$install_path" "$backup_path"
fi
mv "$staging_path" "$install_path"
/usr/bin/codesign --verify --deep --strict "$install_path"
install_committed=true
rm -rf "$backup_path"
trap - EXIT

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$lsregister" -u "$install_path" 2>/dev/null || true
"$lsregister" -f "$install_path"
mdimport "$install_path"

# A running copy keeps its old executable in memory. Stop only known bundles,
# then launch the canonical Applications copy.
for process_id in ${(f)"$(pgrep -f '/(FocusBreakProbe|Focus Break Assistant)\.app/Contents/MacOS/focus-break-probe' || true)"}; do
    kill -TERM "$process_id" 2>/dev/null || true
done
sleep 1
open "$install_path"

# Remove the prior build-only bundle after its process has stopped. The sole
# launch target is now the installed App above.
rm -rf "$bundle_path" "$iconset_path" "$dmg_root" "$legacy_bundle_path" "$legacy_named_bundle_path"

print -r -- "$install_path"
print -r -- "$dmg_path"
