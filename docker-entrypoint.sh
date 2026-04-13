#!/bin/sh
set -eu

echo "Checking OpenSSL providers..."
openssl list -providers

echo "Starting Gotenberg..."
exec /usr/bin/gotenberg "$@"
