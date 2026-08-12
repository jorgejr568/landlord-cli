#!/usr/bin/env bash
# Builds the drag-to-Applications installer disk image for the macOS app.
#
# Produces `dist/Rentivo-<MARKETING_VERSION>.dmg`: a compressed read-only image holding Rentivo.app,
# an `Applications` symlink, and a generated Finder background that says where to drop the app.
#
#   ./scripts/macos-dmg.sh                     # build Release, then package
#   APP_PATH=/path/to/Rentivo.app ./scripts/macos-dmg.sh   # package an app built elsewhere
#   ./scripts/macos-dmg.sh /path/to/Rentivo.app            # same, positionally
#
# The Finder window layout (icon positions, background, icon and window size) is applied with Finder
# scripting, which needs a logged-in GUI session. Without one — a headless CI runner — that step is
# skipped with a warning and the image is still produced; it just opens with the default Finder
# layout instead of the designed one.
#
# Re-running the script is safe: every intermediate lives in a temporary directory and the output is
# replaced, so repeated runs converge on the same artifact.
set -euo pipefail

unset CDPATH
repo_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
project="$repo_root/macos/Rentivo.xcodeproj"
app_icon="$repo_root/macos/Rentivo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png"
background_renderer="$repo_root/scripts/macos-dmg-background.swift"
dist_dir="$repo_root/dist"

volume_name="Rentivo"
# Must match the canvas and icon centres in scripts/macos-dmg-background.swift.
window_width=540
window_height=380
icon_size=128
app_icon_x=145
app_icon_y=190
applications_icon_x=395
applications_icon_y=190

# The macOS project declares MARKETING_VERSION the same way the iOS one does, and the iOS CI helper
# already parses it (and fails loudly when the build configurations disagree), so reuse it.
export RENTIVO_IOS_CI_LIB_ONLY=1
# shellcheck source=./ios-ci.sh
source "$repo_root/scripts/ios-ci.sh"

log() {
  printf 'macos-dmg: %s\n' "$1"
}

warn() {
  printf 'macos-dmg: %s\n' "$1" >&2
}

fail() {
  warn "$1"
  exit 1
}

for tool in xcodebuild hdiutil swift osascript /usr/libexec/PlistBuddy; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing required tool: $tool"
done

work_dir=$(mktemp -d)
mounted_volume=""
attached_device=""
# Nothing may outlive the script: an attached image left behind would collide with the next run's
# volume name. The device entry is the fallback for an image that attached without mounting.
cleanup() {
  if [ -n "$mounted_volume" ]; then
    hdiutil detach "$mounted_volume" -quiet >/dev/null 2>&1 || true
  elif [ -n "$attached_device" ]; then
    hdiutil detach "$attached_device" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

# Prints the first mount point recorded in an `hdiutil attach -plist` result. The entity list holds
# one entry per partition and only the mountable one carries a mount-point key, so entries are
# probed rather than assumed; the list is always a handful of entries long.
attach_mount_point() {
  local plist=$1 index value
  for index in $(seq 0 15); do
    value=$(/usr/libexec/PlistBuddy -c "Print :system-entities:${index}:mount-point" "$plist" 2>/dev/null) \
      || continue
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done
  return 1
}

# Attaches a disk image, publishing its mount point as $mounted_volume so the exit trap can release
# it. It deliberately assigns a global instead of printing: a command substitution would run the
# attach in a subshell and leave the trap with nothing to detach.
attach_image() {
  local image=$1
  shift
  local plist="$work_dir/attach.plist"
  hdiutil attach "$image" -plist -nobrowse -noautoopen "$@" > "$plist"
  attached_device=$(/usr/libexec/PlistBuddy -c "Print :system-entities:0:dev-entry" "$plist" 2>/dev/null || true)
  mounted_volume=$(attach_mount_point "$plist") \
    || fail "hdiutil attached $image without reporting a mount point"
}

detach_image() {
  hdiutil detach "$mounted_volume" -quiet
  mounted_volume=""
  attached_device=""
}

version=$(marketing_version "$repo_root/macos/Rentivo.xcodeproj/project.pbxproj")
output="$dist_dir/Rentivo-${version}.dmg"
log "packaging version $version"

# --- The application bundle ---

app_path=${APP_PATH:-${1:-}}
if [ -z "$app_path" ]; then
  derived_data="$work_dir/DerivedData"
  log "building Release into $derived_data"
  xcodebuild -project "$project" -scheme Rentivo -configuration Release \
    -derivedDataPath "$derived_data" build CODE_SIGN_IDENTITY=-
  app_path="$derived_data/Build/Products/Release/Rentivo.app"
fi
[ -d "$app_path" ] || fail "no application bundle at $app_path"

# --- Staging ---

staging="$work_dir/staging"
mkdir -p "$staging/.background"
cp -R "$app_path" "$staging/Rentivo.app"
ln -s /Applications "$staging/Applications"
swift "$background_renderer" "$app_icon" "$staging/.background/background.png"

# --- The writable image the Finder layout is applied to ---

# `hdiutil create -srcfolder` sizes the image to its contents, leaving no room for the .DS_Store
# Finder writes, so the size is set explicitly with headroom.
staged_megabytes=$(du -sm "$staging" | awk '{print $1}')
image_megabytes=$((staged_megabytes + 64))
readwrite_image="$work_dir/rentivo-readwrite.dmg"
hdiutil create -srcfolder "$staging" -volname "$volume_name" -fs HFS+ \
  -format UDRW -size "${image_megabytes}m" -quiet "$readwrite_image"

attach_image "$readwrite_image" -readwrite -noverify
log "staged volume mounted at $mounted_volume"

# --- Finder layout, best effort ---

# Finder scripting needs a GUI session. On a headless runner the `tell` fails immediately; the image
# is still valid, it just carries no custom layout, so the failure is reported and not fatal.
layout_script="$work_dir/layout.applescript"
cat > "$layout_script" <<APPLESCRIPT
on run argv
  set volumeName to item 1 of argv
  tell application "Finder"
    tell disk volumeName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 160, ${window_width} + 200, ${window_height} + 160}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to ${icon_size}
      set text size of viewOptions to 13
      set background picture of viewOptions to file ".background:background.png"
      set position of item "Rentivo.app" of container window to {${app_icon_x}, ${app_icon_y}}
      set position of item "Applications" of container window to {${applications_icon_x}, ${applications_icon_y}}
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
APPLESCRIPT

# Finder addresses the volume by name, which gains a " 1" suffix if another Rentivo volume is
# already mounted, so the name is read back from the mount point rather than assumed.
volume_label=$(basename "$mounted_volume")
if osascript "$layout_script" "$volume_label" >/dev/null 2>"$work_dir/layout.log"; then
  log "applied the Finder window layout"
else
  warn "Finder scripting is unavailable, so the disk image keeps the default Finder layout."
  warn "This is expected on headless runners; the image itself is unaffected."
  sed 's/^/macos-dmg: osascript: /' "$work_dir/layout.log" >&2 || true
fi

# Give Finder a moment to flush .DS_Store before the volume goes away.
sync
detach_image

# --- Compression and verification ---

mkdir -p "$dist_dir"
rm -f "$output"
hdiutil convert "$readwrite_image" -format UDZO -imagekey zlib-level=9 -quiet -o "$output"

attach_image "$output" -readonly
[ -x "$mounted_volume/Rentivo.app/Contents/MacOS/Rentivo" ] \
  || fail "the built image has no runnable Rentivo.app"
[ -L "$mounted_volume/Applications" ] \
  || fail "the built image has no Applications symlink"
[ "$(readlink "$mounted_volume/Applications")" = "/Applications" ] \
  || fail "the Applications symlink does not point at /Applications"
[ -f "$mounted_volume/.background/background.png" ] \
  || fail "the built image has no Finder background"
detach_image

log "wrote ${output#"$repo_root"/} ($(du -h "$output" | awk '{print $1}'))"
