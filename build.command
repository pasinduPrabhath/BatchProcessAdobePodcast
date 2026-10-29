#!/bin/bash
cd "$(dirname "$0")"
pkill -x AudioBatch 2>/dev/null
sleep 1
bash build.sh 2>&1 | tee build.log
echo "EXIT: ${PIPESTATUS[0]}" >> build.log
