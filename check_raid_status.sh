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
    MDADM_INFO_FILE="/tmp/mdadm_detail"
else
    MDSTAT="/proc/mdstat"
fi

############################################
# DETECT RAID DEVICE
############################################

MD_NAME=$(grep -oE '^md[0-9]+' "$MDSTAT" | head -n1)

if [ -z "$MD_NAME" ]; then
    echo "UNKNOWN - No RAID device found"
    exit $STATE_UNKNOWN
fi

MD_DEVICE="/dev/$MD_NAME"

############################################
# GET RAID DETAILS
############################################

if [ "$TEST_MODE" == "1" ]; then
    LD_INFO=$(cat "$MDADM_INFO_FILE")
else
    LD_INFO=$(mdadm --detail "$MD_DEVICE" 2>/dev/null)
fi

if [ -z "$LD_INFO" ]; then
    echo "UNKNOWN - Cannot read RAID details"
    exit $STATE_UNKNOWN
fi

############################################
# PARSE STATUS
############################################

LD_STATUS=$(echo "$LD_INFO" | awk -F: '/State|status/ {gsub(/^ +| +$/,"",$2); print $2}' | head -n1)

############################################
# DETECT FAILED DISKS
############################################

FAILED_DISKS=$(echo "$LD_INFO" | awk '
/faulty|removed|failed|Missing/ {
    print $NF
}
' | paste -sd "," -)

############################################
# DETECT REBUILD
############################################

REBUILDING=$(echo "$LD_INFO" | grep -i "rebuild\|recovery")
REBUILD_PCT=$(echo "$REBUILDING" | grep -oE '[0-9]+' | head -n1)

############################################
# DETECT DEGRADED STATE FROM MDSTAT
############################################

DEGRADED=$(grep -E "\[U_\]|\[_U\]|\[__\]" "$MDSTAT")

############################################
# LOGIC ENGINE
############################################

# CRITICAL: failed disks or fully broken RAID
if [ -n "$FAILED_DISKS" ] || echo "$DEGRADED" | grep -q "\[__\]"; then
    echo "CRITICAL - RAID failure on $MD_DEVICE - failed_disks=${FAILED_DISKS:-none}"
    exit $STATE_CRITICAL
fi

# WARNING: rebuilding or degraded
if [ -n "$REBUILDING" ] || [ -n "$DEGRADED" ]; then
    if [ -n "$REBUILD_PCT" ]; then
        echo "WARNING - RAID rebuilding (${REBUILD_PCT}%) on $MD_DEVICE"
    else
        echo "WARNING - RAID degraded on $MD_DEVICE"
    fi
    exit $STATE_WARNING
fi

# OK
echo "OK - RAID healthy on $MD_DEVICE (${LD_STATUS:-unknown})"
exit $STATE_OK