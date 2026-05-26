#!/bin/sh
# Build GUI assets on the host before ports build.
# Called by build-ports.py to avoid npm 4 bugs in the poudriere jail.
set -e

GUI_ROOT="$1"
if [ -z "$GUI_ROOT" ]; then
    echo "Usage: build-gui.sh <gui-source-dir>"
    exit 1
fi

NPM="/usr/local/lib/node_modules/corepack/shims/npm"
NODE="/usr/local/bin/node"

cd "$GUI_ROOT"

echo "==> npm install (production deps)"
$NPM install --production 2>&1 | tail -5

echo "==> npm install (build tools)"
$NPM install typescript@2.2.2 postcss postcss-cssnext postcss-import 2>&1 | tail -5

echo "==> TypeScript compile"
./node_modules/.bin/tsc || true

echo "==> PostCSS build"
$NODE build-css.js

echo "==> UUID bundle"
mkdir -p bin/vendors/uuid/lib
cp node_modules/uuid/index.js bin/vendors/uuid/index.js
cp node_modules/uuid/v1.js bin/vendors/uuid/v1.js
cp node_modules/uuid/v4.js bin/vendors/uuid/v4.js
cp node_modules/uuid/lib/bytesToUuid.js bin/vendors/uuid/lib/bytesToUuid.js
cp node_modules/uuid/lib/rng-browser.js bin/vendors/uuid/lib/rng.js

echo "==> Cleaning node_modules"
rm -rf node_modules

echo "==> GUI build complete"
