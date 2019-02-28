#!/bin/bash

# Note that this does not use pipefail
# because if the grep later doesn't match any deleted files,
# which is likely the majority case,
# it does not exit with a 0, and I only care about the final exit.
set -eo

# Ensure SVN username and password are set
# IMPORTANT: secrets are accessible by anyone with write access to the repository!
if [[ -z "$WORDPRESS_USERNAME" ]]; then
	echo "Set the WORDPRESS_USERNAME secret"
	exit 1
fi

if [[ -z "$WORDPRESS_PASSWORD" ]]; then
	echo "Set the WORDPRESS_PASSWORD secret"
	exit 1
fi

# Allow some ENV variables to be customized
if [[ -z "$SLUG" ]]; then
	SLUG=${GITHUB_REPOSITORY#*/}
fi
echo "ℹ︎ SLUG is $SLUG"

# Set VERSION value according to tag value.
VERSION=${GITHUB_REF#refs/tags/}
echo "ℹ︎ VERSION is $VERSION"

SVN_URL="http://plugins.svn.wordpress.org/${SLUG}/"
SVN_DIR="/github/svn-${SLUG}"

# Checkout just trunk and assets for efficiency
# Tagging will be handled on the SVN level
echo "➤ Checking out .org repository..."
svn checkout --depth immediates "$SVN_URL" "$SVN_DIR"
cd "$SVN_DIR"
svn update --set-depth infinity assets
svn update --set-depth infinity trunk

echo "➤ Copying files..."

# Copy from current branch to /trunk, excluding dotorg assets
# The --delete flag will delete anything in destination that no longer exists in source
rsync -r --exclude "/$ASSETS_DIR/" --exclude ".git/" --exclude ".github/" "$GITHUB_WORKSPACE/" trunk/ --delete

if [[ ! -z "$ASSETS_DIR" ]]; then
    # Copy dotorg assets to /assets
    rsync -r "$GITHUB_WORKSPACE/$ASSETS_DIR/" assets/ --delete
fi

# Add everything and commit to SVN
# The force flag ensures we recurse into subdirectories even if they are already added
# Suppress stdout in favor of svn status later for readability
echo "➤ Preparing files..."
svn add . --force > /dev/null

# SVN delete all deleted files
# Also suppress stdout here
svn status | grep '^\!' | sed 's/! *//' | xargs -I% svn rm % > /dev/null

svn status

echo "︎➤ Committing files..."
#svn commit -m "Update to version $VERSION from GitHub" --no-auth-cache --non-interactive  --username "$WORDPRESS_USERNAME" --password "$WORDPRESS_PASSWORD"

# SVN tag to VERSION
echo "➤ Tagging version..."
#svn cp "^/$SLUG/trunk" "^/$SLUG/tags/$VERSION" -m "Tag $VERSION" --no-auth-cache --non-interactive --username "$WORDPRESS_USERNAME" --password "$WORDPRESS_PASSWORD"

echo "✓ Plugin deployed!"
