#!/bin/sh
# Pulls the images and gives them neutral local names, so `docker images` / `docker ps` don't show
# the original names. Then set APP_IMAGE / HELPER_IMAGE in .env as printed below.
set -e
docker pull ghcr.io/suwayomi/suwayomi-server:stable
docker pull ghcr.io/flaresolverr/flaresolverr:latest
docker tag ghcr.io/suwayomi/suwayomi-server:stable cache-app:local
docker tag ghcr.io/flaresolverr/flaresolverr:latest cache-helper:local
docker rmi ghcr.io/suwayomi/suwayomi-server:stable ghcr.io/flaresolverr/flaresolverr:latest
echo "Add to .env:"
echo "APP_IMAGE=cache-app:local"
echo "HELPER_IMAGE=cache-helper:local"
