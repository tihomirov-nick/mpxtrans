#!/bin/bash
# Publishes a GitHub release: builds dist/Slovo-<version>.dmg from the committed code, checks that the app in it is
# signed with the author's certificate, tags v<version>, pushes main and the tag, then publishes the release with
# the DMG attached. Installed copies of Slovo find the release themselves and offer to update.
#   VERSION=1.2.0 NOTES=~/notes-1.2.0.md ./scripts/release.sh     (keep the notes file outside the repo)
# git goes through the remote's deploy key (git@github-mpxtrans:..., see ~/.ssh/config). The release API needs a
# fine-grained token of tihomirov-nick with Contents: Read and write on this repo, kept in the Keychain
# (account tihomirov-nick, service TOKEN_SERVICE; by default github-slovo-token).
# gh's own login is a different account and is not used. Without such a token the script stops before the build.
# The app must be signed with the self-signed certificate "tihomirov-nick" from the login Keychain: installed copies
# accept only updates signed with it, so without it the script stops too.
# Safe to re-run: an existing tag on HEAD and an existing (draft) release are reused.
set -euo pipefail

VERSION="${VERSION:?set VERSION, e.g. VERSION=1.2.0}"
NOTES="${NOTES:?set NOTES to a Markdown file with the release notes}"
[ -f "$NOTES" ] || { echo "no notes file: $NOTES"; exit 1; }
NOTES="$(cd "$(dirname "$NOTES")" && pwd)/$(basename "$NOTES")"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REPO="tihomirov-nick/slovo"
SERVICES="${TOKEN_SERVICE:-github-slovo-token}"
IDENTITY="tihomirov-nick"
TAG="v$VERSION"
DMG="dist/Slovo-$VERSION.dmg"

# 1. The release must match committed code on main, and be signed with the certificate updates are checked against
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "switch to main first"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "commit or stash changes first (untracked files count too)"; exit 1; }
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && [ "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]; then
    echo "$TAG already points to another commit"; exit 1
fi
security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\"" || {
    echo "no certificate \"$IDENTITY\" in the Keychain: installed copies could not update to this release"; exit 1
}

# 2. Token, checked by creating the draft release before anything is built or pushed
TOKEN=""
for service in $SERVICES; do
    TOKEN="$(security find-generic-password -a tihomirov-nick -s "$service" -w 2>/dev/null)" && break
done
[ -n "$TOKEN" ] || { echo "no GitHub token in the Keychain (account tihomirov-nick, tried: $SERVICES)"; exit 1; }
gh_() { GH_TOKEN="$TOKEN" gh "$@"; }
if ! gh_ release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh_ release create "$TAG" --repo "$REPO" --draft --title "Slovo $VERSION" --notes-file "$NOTES" >/dev/null || {
        echo "the token from Keychain service $service can't create releases in $REPO"
        echo "(it needs Contents: Read and write on this repo; nothing was built or pushed)"
        exit 1
    }
fi

# 3. Build (build_app.sh regenerates Localizable.strings, which is tracked)
SIGN_IDENTITY="$IDENTITY" VERSION="$VERSION" ./scripts/make_dmg.sh
[ -z "$(git status --porcelain)" ] || { echo "the build changed tracked files, commit them and run again:"; git status --short; exit 1; }

# 4. The app in the DMG: this version, signed with the certificate (the requirement installed copies check)
./scripts/verify_dmg.sh "$DMG" "$VERSION" || { echo "not published: the DMG would not update installed copies"; exit 1; }

# 5. Tag and push
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git tag -a "$TAG" -m "Slovo $VERSION"
git push origin main "$TAG"

# 6. Attach the DMG and publish
gh_ release upload "$TAG" "$DMG" --repo "$REPO" --clobber
gh_ release edit "$TAG" --repo "$REPO" --draft=false --title "Slovo $VERSION" --notes-file "$NOTES"
echo "==> https://github.com/$REPO/releases/tag/$TAG"
