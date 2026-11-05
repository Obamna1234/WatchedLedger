#!/usr/bin/env bash
# Prepares a fresh clone for building.
#
# The repo commits only the platform files we customise (signing, permissions,
# network security, Info.plist). `flutter create` fills in the rest of the
# standard Android/iOS boilerplate and never overwrites files that already exist.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create \
  --project-name watchedledger \
  --org app \
  --platforms android,ios \
  --no-pub \
  .

flutter pub get
dart run build_runner build --delete-conflicting-outputs
echo "Bootstrap complete."
