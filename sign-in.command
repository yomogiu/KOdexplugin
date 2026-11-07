#!/bin/zsh
set -eu
cd -- "${0:A:h}"
unset NODE_OPTIONS NODE_EXTRA_CA_CERTS SSLKEYLOGFILE
kobo_node_bin=$(/usr/bin/plutil -extract nodeBinary raw -o - .private/bridge.json)
exec "$kobo_node_bin" login.mjs
