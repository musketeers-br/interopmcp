#!/bin/sh
set -e
# O Dockerfile.web já roda nginx + node via CMD
exec "$@"
