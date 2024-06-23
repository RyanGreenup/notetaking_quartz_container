#!/bin/sh
while :; do
    find ./content |\
        entr -d -n  \
        ./run_quartz.sh
done
