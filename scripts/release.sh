#!/bin/bash
# Publishes a Daybook release that installed copies update to:
#
#   scripts/release.sh 1.1.0             raise the version, test, build, sign,
#                                        tag, push and upload to GitHub Releases
#   scripts/release.sh 1.1.0 --dry-run   everything up to the upload, then puts
#                                        build.sh back and publishes nothing
#
# The update is signed with the EdDSA key in the login Keychain (account
# Daybook); installed copies accept only updates signed by it. The
# feed (appcast.xml) is uploaded with each release, and the app reads the
# latest one from releases/latest/download/appcast.xml.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

REPO="prabeshbhetwal/Daybook"
KEY_ACCOUNT="Daybook"
APP_NAME="Daybook"

VERSION="${1:-}"
DRY_RUN=0
case "${2:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  # Anything else is a mistake, never a quiet real release: "--dryrun"
  # once fell through to commit, tag, push and publish.
  *) echo "usage: $0 <major.minor.patch> [--dry-run]" >&2; exit 2 ;;
esac
if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ "$#" -gt 2 ]; then
  echo "usage: $0 <major.minor.patch> [--dry-run]" >&2
  exit 2
fi

fail() { echo "error: $*" >&2; exit 1; }

# What is released is what is committed on main, and nothing else.
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || [ "${DRY_RUN}" -eq 1 ] || fail "release from main"
[ -z "$(git status --porcelain)" ] || fail "commit or set aside your changes first"
git rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null && fail "v${VERSION} is already tagged"
if [ "${DRY_RUN}" -eq 0 ]; then
  # Installed copies fetch the feed without credentials: a private repo
  # serves them nothing.
  [ "$(gh repo view "${REPO}" --json visibility --jq .visibility)" = "PUBLIC" ] \
    || fail "${REPO} is private, so installed copies could not download this release"
  # A push that would be refused must fail here, before anything is
  # committed or tagged, not after.
  git fetch -q origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || fail "local main and origin/main differ; pull or push first"
fi

CURRENT_VERSION="$(sed -n 's/^APP_VERSION="\(.*\)"$/\1/p' build.sh)"
CURRENT_BUILD="$(sed -n 's/^APP_BUILD="\(.*\)"$/\1/p' build.sh)"
[ -n "${CURRENT_VERSION}" ] && [ -n "${CURRENT_BUILD}" ] || fail "build.sh has no APP_VERSION/APP_BUILD"
if [ "$(printf '%s\n%s\n' "${CURRENT_VERSION}" "${VERSION}" | sort -V | tail -1)" != "${VERSION}" ] \
   || [ "${CURRENT_VERSION}" = "${VERSION}" ]; then
  fail "${VERSION} is not newer than ${CURRENT_VERSION}"
fi
# The updater compares build numbers: each release's must be larger.
NEW_BUILD=$((CURRENT_BUILD + 1))

SPARKLE="$(scripts/fetch-sparkle.sh)"
PUBLIC_KEY="$(sed -n 's/^UPDATE_PUBLIC_KEY="\(.*\)"$/\1/p' build.sh)"
KEYCHAIN_KEY="$("${SPARKLE}/bin/generate_keys" --account "${KEY_ACCOUNT}" -p 2>/dev/null | tail -1)"
[ "${KEYCHAIN_KEY}" = "${PUBLIC_KEY}" ] \
  || fail "the Keychain key (account ${KEY_ACCOUNT}) does not match UPDATE_PUBLIC_KEY in build.sh"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-release.XXXXXX")"
cp build.sh "${STAGE}/build.sh.before"
# Before the release commit, a stop puts build.sh back. After it, the
# commit is the truth: build.sh is left as committed, and the signed zip and
# feed are kept in .build/release-<version>/ so the upload can be retried.
COMMITTED=0
restore_build_script() {
  if [ "${COMMITTED}" -eq 0 ]; then
    cp "${STAGE}/build.sh.before" build.sh
  elif [ "${PUBLISHED:-0}" -ne 1 ]; then
    echo "error: the release commit and tag exist, but publishing did not finish." >&2
    echo "Kept: ${KEEP}. To finish:" >&2
    echo "  git push origin main v${VERSION}" >&2
    echo "  gh release create v${VERSION} ${KEEP}/${ZIP_NAME} ${KEEP}/appcast.xml --repo ${REPO} --title \"${APP_NAME} ${VERSION}\" --notes-file ${KEEP}/notes.md" >&2
  fi
  rm -rf "${STAGE}"
}
trap restore_build_script EXIT

echo "Releasing ${VERSION} (build ${NEW_BUILD}) after ${CURRENT_VERSION} (build ${CURRENT_BUILD})…"
sed -i '' -e "s/^APP_VERSION=\".*\"$/APP_VERSION=\"${VERSION}\"/" \
          -e "s/^APP_BUILD=\".*\"$/APP_BUILD=\"${NEW_BUILD}\"/" build.sh

# Every self-test passes, and the tested bundle is the one that ships.
./build.sh --test

# Signed and checked in a plain folder: a synced checkout tags files with
# attributes that strict verification rejects.
APP="${STAGE}/${APP_NAME}.app"
ditto "${ROOT}/${APP_NAME}.app" "${APP}"
xattr -cr "${APP}"
codesign --verify --deep --strict "${APP}"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP}/Contents/Info.plist")"
BUILT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${APP}/Contents/Info.plist")"
[ "${BUILT_VERSION}" = "${VERSION}" ] && [ "${BUILT_BUILD}" = "${NEW_BUILD}" ] \
  || fail "the built app says ${BUILT_VERSION} (${BUILT_BUILD}), not ${VERSION} (${NEW_BUILD})"

ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP="${STAGE}/${ZIP_NAME}"
ditto -c -k --norsrc --noextattr --keepParent "${APP}" "${ZIP}"
# `sparkle:edSignature="…" length="…"`, for the feed's enclosure.
SIGNATURE="$("${SPARKLE}/bin/sign_update" --account "${KEY_ACCOUNT}" "${ZIP}")"
"${SPARKLE}/bin/sign_update" --account "${KEY_ACCOUNT}" --verify "${ZIP}" \
  "$(echo "${SIGNATURE}" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')" >/dev/null \
  || fail "the update's signature did not verify"

# Release notes: the commit subjects since the last release (the last 20
# for the first one, rather than the project's whole history).
LAST_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
if [ -n "${LAST_TAG}" ]; then RANGE=("${LAST_TAG}..HEAD"); else RANGE=(-n 20); fi
SUBJECTS="${STAGE}/subjects.txt"
git log --no-merges --pretty='%s' "${RANGE[@]}" | grep -v '^Version [0-9]' > "${SUBJECTS}" || true
NOTES="${STAGE}/notes.md"
{
  echo "## What's new in ${VERSION}"
  echo
  sed 's/^/- /' "${SUBJECTS}"
} > "${NOTES}"
NOTES_HTML="$(sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
                  -e 's/^/<li>/' -e 's/$/<\/li>/' "${SUBJECTS}" | tr -d '\n')"

cat > "${STAGE}/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>${APP_NAME}</title>
    <link>https://github.com/${REPO}</link>
    <description>Updates for ${APP_NAME}</description>
    <language>en</language>
    <item>
      <title>${APP_NAME} ${VERSION}</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>${NEW_BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>${NOTES_HTML}</ul>]]></description>
      <enclosure url="https://github.com/${REPO}/releases/download/v${VERSION}/${ZIP_NAME}"
                 ${SIGNATURE}
                 type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

if [ "${DRY_RUN}" -eq 1 ]; then
  OUT="${ROOT}/.build/release-dry-run"
  rm -rf "${OUT}" && mkdir -p "${OUT}"
  cp "${ZIP}" "${STAGE}/appcast.xml" "${NOTES}" "${OUT}/"
  echo "Dry run: nothing committed, tagged or uploaded. build.sh is back to ${CURRENT_VERSION}."
  echo "Artifacts: ${OUT}"
  exit 0
fi

KEEP="${ROOT}/.build/release-${VERSION}"
rm -rf "${KEEP}" && mkdir -p "${KEEP}"
cp "${ZIP}" "${STAGE}/appcast.xml" "${NOTES}" "${KEEP}/"

git add build.sh
git commit -q -m "Version ${VERSION}"
git tag -a "v${VERSION}" -m "${APP_NAME} ${VERSION}"
COMMITTED=1
git push origin main "v${VERSION}"
gh release create "v${VERSION}" "${KEEP}/${ZIP_NAME}" "${KEEP}/appcast.xml" \
  --repo "${REPO}" --title "${APP_NAME} ${VERSION}" --notes-file "${KEEP}/notes.md"
PUBLISHED=1

# What installed copies will read, read the way they read it.
FEED="https://github.com/${REPO}/releases/latest/download/appcast.xml"
curl -fsSL "${FEED}" | grep -q "<sparkle:version>${NEW_BUILD}</sparkle:version>" \
  || echo "warning: ${FEED} does not list build ${NEW_BUILD} yet; GitHub may still be caching" >&2
echo "Released ${APP_NAME} ${VERSION}: https://github.com/${REPO}/releases/tag/v${VERSION}"
