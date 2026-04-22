#!/bin/bash

STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3

############################################
# MODE SETUP
############################################

if [ "$TEST_MODE" == "1" ]; then
    MDSTAT="/tmp/mdstat"
else
    MDSTAT="/proc/mdstat"
fi

############################################
# VALIDATE INPUT FILE
############################################

if [ ! -f "$MDSTAT" ]; then
    echo "UNKNOWN - Cannot access $MDSTAT"
    exit $STATE_UNKNOWN
fi

############################################
# DETECT RAID DEVICE(S)
############################################

MD_LIST=$(awk '/^md[0-9]+/ {print $1}' "$MDSTAT")

if [ -z "$MD_LIST" ]; then
    echo "UNKNOWN - No RAID device found"
    exit $STATE_UNKNOWN
fi

############################################
# INITIAL STATUS FLAGS
############################################

CRITICAL_FLAG=0
WARNING_FLAG=0
OUTPUT_MSG=""

############################################
# LOOP THROUGH ALL MD DEVICES
############################################

for MD_NAME in $MD_LIST; do

    MD_DEVICE="/dev/$MD_NAME"

    RAID_LINE=$(grep -E "^$MD_NAME" "$MDSTAT")

    STATUS=$(echo "$RAID_LINE" | grep -o "\[.*\]" | tail -n1)

    # Detect degraded arrays
    if echo "$STATUS" | grep -q "\[_\]"; then
        WARNING_FLAG=1
        OUTPUT_MSG+="WARNING - $MD_NAME is degraded; "
    fi

    # Detect failed arrays
    if echo "$STATUS" | grep -q "\[__\]"; then
        CRITICAL_FLAG=1
        OUTPUT_MSG+="CRITICAL - $MD_NAME is broken; "
    fi

    # Detect rebuilding
    if echo "$RAID_LINE" | grep -qi "rebuild\|recovery"; then
        REBUILD_PCT=$(echo "$RAID_LINE" | grep -oE '[0-9]+' | head -n1)
        WARNING_FLAG=1
        OUTPUT_MSG+="REBUILDING $MD_NAME (${REBUILD_PCT}%) ; "
    fi

    # Healthy state
    if [ "$CRITICAL_FLAG" -eq 0 ] && [ "$WARNING_FLAG" -eq 0 ]; then
        OUTPUT_MSG+="OK - $MD_NAME healthy; "
    fi

done

############################################
# FINAL DECISION ENGINE
############################################

if [ "$CRITICAL_FLAG" -eq 1 ]; then
    echo "CRITICAL - RAID failure detected | $OUTPUT_MSG"
    exit $STATE_CRITICAL
fi

if [ "$WARNING_FLAG" -eq 1 ]; then
    echo "WARNING - RAID degraded or rebuilding | $OUTPUT_MSG"
    exit $STATE_WARNING
fi

echo "OK - All RAID arrays healthy | $OUTPUT_MSG"
exit $STATE_OK