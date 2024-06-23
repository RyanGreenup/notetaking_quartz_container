#!/bin/sh
# build.sh
# Timeout will give up if this takes longer than the specified time
timeout 300 /usr/bin/npx quartz build --concurrency 4 &&\
    cp -r public/* public_host/ &&\
    echo "BUILD DONE--------------------------------------------"
