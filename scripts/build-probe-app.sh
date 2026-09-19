#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
bundle_name="Focus Break Assistant.app"
bundle_path="$project_root/.build/$bundle_name"
legacy_bundle_path="$project_root/.build/FocusBreakProbe.app"
contents_path="$bundle_path/Contents"
resource_bundle_name="FocusBreakAssistant_FocusBreakProbe.bundle"
install_directory="/Applications"
install_path="$install_directory/$bundle_name"
staging_path="$install_directory/.FocusBreakAssistant-install-$$"
backup_path="$install_directory/.FocusBreakAssistant-previous-$$"
install_committed=false

cd "$project_root"
swift build -c release

rm -rf "$bundle_path"
mkdir -p "$contents_path/MacOS"
mkdir -p "$contents_path/Resources"
cp "$project_root/.build/release/focus-break-probe" "$contents_path/MacOS/focus-break-probe"
rm -rf "$contents_path/Resources/$resource_bundle_name"
cp -R "$project_root/.build/release/$resource_bundle_name" "$contents_path/Resources/$resource_bundle_name"
cp "$project_root/Support/FocusBreakProbe-Info.plist" "$contents_path/Info.plist"
/usr/bin/xcrun actool "$project_root/Support/Assets.xcassets" \
    --compile "$contents_path/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$project_root/.build/AppIcon-Info.plist"
/usr/bin/codesign --force --sign - "$bundle_path"

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

# A running copy keeps its old executable in memory. Stop only known bundles,
# then launch the canonical Applications copy.
for process_id in ${(f)"$(pgrep -f '/(FocusBreakProbe|Focus Break Assistant)\.app/Contents/MacOS/focus-break-probe' || true)"}; do
    kill -TERM "$process_id" 2>/dev/null || true
done
sleep 1
open "$install_path"

# Remove the prior build-only bundle after its process has stopped. The sole
# launch target is now the installed App above.
rm -rf "$legacy_bundle_path"

print -r -- "$install_path"
