#!/usr/bin/env bash

set -euo pipefail

EXPECTED_VERSION=0.3.0
PACKAGE_NAME=CmdABC-$EXPECTED_VERSION
ARCHIVE_NAME=$PACKAGE_NAME.tar.gz

SCRIPT_DIR=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
REPO_DIR=${SCRIPT_DIR%/scripts}
OUTPUT_DIR=$REPO_DIR/artifacts
ARCHIVE_PATH=$OUTPUT_DIR/$ARCHIVE_NAME
CHECKSUM_PATH=$ARCHIVE_PATH.sha256
STAGING_DIR=''
ARCHIVE_TEMP=''
CHECKSUM_TEMP=''
TAR_OWNER_ARGS=()

package_error() {
  printf 'cmdabc package: %s\n' "$*" >&2
}

package_fail() {
  package_error "$*"
  exit 1
}

package_cleanup() {
  if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
    rm -rf "$STAGING_DIR"
  fi
  if [ -n "$ARCHIVE_TEMP" ] && [ -e "$ARCHIVE_TEMP" ]; then
    rm -f "$ARCHIVE_TEMP"
  fi
  if [ -n "$CHECKSUM_TEMP" ] && [ -e "$CHECKSUM_TEMP" ]; then
    rm -f "$CHECKSUM_TEMP"
  fi
}

trap package_cleanup EXIT
trap 'exit 130' INT TERM HUP

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    package_fail 'neither shasum nor sha256sum is available'
  fi
}

copy_release_file() {
  local source=$1
  local destination=$2

  [ -f "$source" ] || package_fail "required file is missing: $source"
  [ ! -L "$source" ] || package_fail "required file must not be a symlink: $source"
  cp "$source" "$destination" || package_fail "cannot copy release file: $source"
}

export LC_ALL=C
export TZ=UTC
umask 022

[ -f "$REPO_DIR/VERSION" ] || package_fail 'VERSION is missing'
IFS= read -r VERSION < "$REPO_DIR/VERSION" || package_fail 'cannot read VERSION'
[ "$VERSION" = "$EXPECTED_VERSION" ] \
  || package_fail "VERSION must be $EXPECTED_VERSION, found ${VERSION:-empty}"

RUNTIME_VERSION=$("$REPO_DIR/prototype/cmdabc" --version) \
  || package_fail 'cannot read cmdabc --version'
[ "$RUNTIME_VERSION" = "$EXPECTED_VERSION" ] \
  || package_fail "cmdabc --version must be $EXPECTED_VERSION, found $RUNTIME_VERSION"

mkdir -p "$OUTPUT_DIR" || package_fail "cannot create output directory: $OUTPUT_DIR"
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cmdabc-package.XXXXXX") \
  || package_fail 'cannot create staging directory'
PACKAGE_ROOT=$STAGING_DIR/$PACKAGE_NAME
mkdir -p "$PACKAGE_ROOT/shell" "$PACKAGE_ROOT/docs/images" \
  || package_fail 'cannot create package staging layout'

# Release contents are an explicit allowlist. Development files are never copied.
copy_release_file "$REPO_DIR/prototype/cmdabc" "$PACKAGE_ROOT/cmdabc"
copy_release_file "$REPO_DIR/install.sh" "$PACKAGE_ROOT/install.sh"
copy_release_file "$REPO_DIR/uninstall.sh" "$PACKAGE_ROOT/uninstall.sh"
copy_release_file "$REPO_DIR/VERSION" "$PACKAGE_ROOT/VERSION"
copy_release_file "$REPO_DIR/README.md" "$PACKAGE_ROOT/README.md"
copy_release_file "$REPO_DIR/README.zh-CN.md" "$PACKAGE_ROOT/README.zh-CN.md"
copy_release_file "$REPO_DIR/LICENSE" "$PACKAGE_ROOT/LICENSE"
copy_release_file "$REPO_DIR/docs/images/cmdabc-01-command-tree.png" \
  "$PACKAGE_ROOT/docs/images/cmdabc-01-command-tree.png"
copy_release_file "$REPO_DIR/docs/images/cmdabc-02-management.png" \
  "$PACKAGE_ROOT/docs/images/cmdabc-02-management.png"
copy_release_file "$REPO_DIR/docs/images/cmdabc-03-command-fill.png" \
  "$PACKAGE_ROOT/docs/images/cmdabc-03-command-fill.png"
copy_release_file "$REPO_DIR/docs/images/cmdabc-04-list.png" \
  "$PACKAGE_ROOT/docs/images/cmdabc-04-list.png"
copy_release_file "$REPO_DIR/docs/images/cmdabc-05-add.png" \
  "$PACKAGE_ROOT/docs/images/cmdabc-05-add.png"
copy_release_file "$REPO_DIR/prototype/shell/cmdabc.bash" "$PACKAGE_ROOT/shell/cmdabc.bash"
copy_release_file "$REPO_DIR/prototype/shell/cmdabc.zsh" "$PACKAGE_ROOT/shell/cmdabc.zsh"

chmod 755 "$PACKAGE_ROOT" "$PACKAGE_ROOT/shell" \
  "$PACKAGE_ROOT/docs" "$PACKAGE_ROOT/docs/images"
chmod 755 "$PACKAGE_ROOT/cmdabc" "$PACKAGE_ROOT/install.sh" "$PACKAGE_ROOT/uninstall.sh"
chmod 644 "$PACKAGE_ROOT/VERSION" "$PACKAGE_ROOT/README.md" \
  "$PACKAGE_ROOT/README.zh-CN.md" "$PACKAGE_ROOT/LICENSE" \
  "$PACKAGE_ROOT/shell/cmdabc.bash" "$PACKAGE_ROOT/shell/cmdabc.zsh" \
  "$PACKAGE_ROOT/docs/images/cmdabc-01-command-tree.png" \
  "$PACKAGE_ROOT/docs/images/cmdabc-02-management.png" \
  "$PACKAGE_ROOT/docs/images/cmdabc-03-command-fill.png" \
  "$PACKAGE_ROOT/docs/images/cmdabc-04-list.png" \
  "$PACKAGE_ROOT/docs/images/cmdabc-05-add.png"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$PACKAGE_ROOT" || package_fail 'cannot clear staging extended attributes'
fi

if find "$PACKAGE_ROOT" \( -name '.DS_Store' -o -name '._*' \) -print | grep -q .; then
  package_fail 'staging contains macOS metadata files'
fi
if find "$PACKAGE_ROOT" -type l -print | grep -q .; then
  package_fail 'staging contains a symlink'
fi

# Stable timestamps plus gzip -n make repeated builds byte-identical.
find "$PACKAGE_ROOT" -exec touch -t 200001010000 {} + \
  || package_fail 'cannot normalize staging timestamps'

if tar --version 2>/dev/null | grep -qi bsdtar; then
  TAR_OWNER_ARGS=(--uid 0 --gid 0 --uname root --gname root)
else
  TAR_OWNER_ARGS=(--owner=0 --group=0 --numeric-owner)
fi

ARCHIVE_TEMP=$OUTPUT_DIR/.$ARCHIVE_NAME.tmp.$$
CHECKSUM_TEMP=$OUTPUT_DIR/.$ARCHIVE_NAME.sha256.tmp.$$
rm -f "$ARCHIVE_TEMP" "$CHECKSUM_TEMP"

COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 \
  tar --format ustar --no-recursion "${TAR_OWNER_ARGS[@]}" -cf - \
  -C "$STAGING_DIR" \
  "$PACKAGE_NAME" \
  "$PACKAGE_NAME/cmdabc" \
  "$PACKAGE_NAME/install.sh" \
  "$PACKAGE_NAME/uninstall.sh" \
  "$PACKAGE_NAME/VERSION" \
  "$PACKAGE_NAME/README.md" \
  "$PACKAGE_NAME/README.zh-CN.md" \
  "$PACKAGE_NAME/LICENSE" \
  "$PACKAGE_NAME/docs" \
  "$PACKAGE_NAME/docs/images" \
  "$PACKAGE_NAME/docs/images/cmdabc-01-command-tree.png" \
  "$PACKAGE_NAME/docs/images/cmdabc-02-management.png" \
  "$PACKAGE_NAME/docs/images/cmdabc-03-command-fill.png" \
  "$PACKAGE_NAME/docs/images/cmdabc-04-list.png" \
  "$PACKAGE_NAME/docs/images/cmdabc-05-add.png" \
  "$PACKAGE_NAME/shell" \
  "$PACKAGE_NAME/shell/cmdabc.bash" \
  "$PACKAGE_NAME/shell/cmdabc.zsh" \
  | gzip -n -9 > "$ARCHIVE_TEMP" \
  || package_fail 'cannot create release archive'

if command -v xattr >/dev/null 2>&1; then
  xattr -c "$ARCHIVE_TEMP" || package_fail 'cannot clear archive extended attributes'
fi

mv -f "$ARCHIVE_TEMP" "$ARCHIVE_PATH" || package_fail 'cannot publish release archive'
ARCHIVE_TEMP=''
ARCHIVE_SHA256=$(sha256_file "$ARCHIVE_PATH")
printf '%s  %s\n' "$ARCHIVE_SHA256" "$ARCHIVE_NAME" > "$CHECKSUM_TEMP" \
  || package_fail 'cannot write SHA-256 file'
if command -v xattr >/dev/null 2>&1; then
  xattr -c "$CHECKSUM_TEMP" || package_fail 'cannot clear checksum extended attributes'
fi
mv -f "$CHECKSUM_TEMP" "$CHECKSUM_PATH" || package_fail 'cannot publish SHA-256 file'
CHECKSUM_TEMP=''

printf 'Created %s\n' "$ARCHIVE_PATH"
printf 'Created %s\n' "$CHECKSUM_PATH"
printf 'SHA-256: %s\n' "$ARCHIVE_SHA256"
