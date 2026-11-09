#!/usr/bin/env bash
# All Google Cast tests. Needs python3, openssl, and for the integration test gst-launch-1.0 with x264/hlssink2/fdkaac.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cd "$here/.."
python3 -m unittest discover -s engine -p 'test_*.py'
python3 -m unittest tests/integration.py
