#!/bin/bash

# check_lancom
# Description : Checks LANCOM Router

# MIT License
#
# Copyright (c) 2017 Dennis Michalski
# Copyright (c) 2024 Sven Siemsen
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Revision history:
# 2017-03-03  Created
# 2024-08-18  Add SNMPv3 Support, add WAN connection check and stats

# Commands
CMD_SNMPWALK="$(which snmpwalk)"
CMD_AWK="$(which awk)"
CMD_BC="$(which bc)"
CMD_EXPR="$(which expr)"

# Script name
SCRIPTNAME=$(basename "$0")

# Version
VERSION="1.1"

# Plugin return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_CONNECTED="eConnection(7)"

# OIDs
OID_MEMORYTOTAL="LCOS-MIB::lcsStatusHardwareInfoTotalMemoryKbytes"
OID_MEMORYFREE="LCOS-MIB::lcsStatusHardwareInfoFreeMemoryKbytes"
OID_CPULOAD5S="LCOS-MIB::lcsStatusHardwareInfoCpuLoad5sPercent"
OID_CPULOAD60S="LCOS-MIB::lcsStatusHardwareInfoCpuLoad60sPercent"
OID_CPULOAD300S="LCOS-MIB::lcsStatusHardwareInfoCpuLoad300sPercent"
OID_TEMP="LCOS-MIB::lcsStatusHardwareInfoTemperatureDegrees"
OID_TEMPMAX="LCOS-MIB::lcsSetupTemperatureMonitorUpperLimitDegrees"
OID_TEMPMIN="LCOS-MIB::lcsSetupTemperatureMonitorLowerLimitDegrees"
OID_VPN_CONNECTIONS="LCOS-MIB::lcsStatusVpnTunnel"



# Default variables
DESCRIPTION="Unknown"
STATE=$STATE_UNKNOWN
SNMP_VERSION=1
COMMUNITY="public"
HOSTNAME="192.168.10.1"
TASK=""
WARNING=60
CRITICAL=65
INTERFACE=eDslCh1
CONNECTION_NAME="INTERNET"


# SNMPv3 variables
SEC_LEVEL=""
SEC_NAME=""
AUTH_PROTOCOL=""
AUTH_PASSWORD=""
PRIV_PROTOCOL=""
PRIV_PASSWORD=""

# Functions
print_usage() {
  echo "Usage: $SCRIPTNAME -H 192.168.0.1 -P 1|2|3 -T task -C community -w warning -c critical -I connection_name"
  echo "       $SCRIPTNAME -H 192.168.0.1 -P 3 -l secLevel -u secName -a authProtocol -A authPassword -x privProtocol -X privPassword"
}

print_version() {
  echo "$SCRIPTNAME version $VERSION"
  echo "This nagios plugin comes with ABSOLUTELY NO WARRANTY."
  echo "You may redistribute copies of the plugin under the terms of the MIT License."
}

print_help() {
  print_version
  echo ""
  print_usage
  echo ""
  echo "Checks Lancom Router"
}

size_convert() {
  local value=$1
  if [ "$value" -ge 1073741824 ]; then
    echo "$(echo "scale=2 ; ( ( $value / 1024 ) / 1024 ) / 1024" | $CMD_BC) TiB"
  elif [ "$value" -ge 1048576 ]; then
    echo "$(echo "scale=2 ; ( $value / 1024 ) / 1024" | $CMD_BC) GiB"
  elif [ "$value" -ge 1024 ]; then
    echo "$(echo "scale=2 ; $value / 1024" | $CMD_BC) MiB"
  else
    echo "$value KiB"
  fi
}

snmp_get_value() {
  local oid=$1
  local cmd="$CMD_SNMPWALK -t 2 -r 2 -v $SNMP_VERSION"

  if [ "$SNMP_VERSION" == "3" ]; then
    cmd="$cmd -l $SEC_LEVEL -u $SEC_NAME -a $AUTH_PROTOCOL -A $AUTH_PASSWORD -x $PRIV_PROTOCOL -X $PRIV_PASSWORD $HOSTNAME $oid"
  else
    cmd="$cmd -c $COMMUNITY $HOSTNAME $oid"
  fi

  echo $(eval $cmd | $CMD_AWK '{ print $4 }')
}

while getopts H:P:T:C:w:c:I:l:u:a:A:x:X:hV OPT; do
  case $OPT in
    H) HOSTNAME="$OPTARG" ;;
    P) SNMP_VERSION="$OPTARG" ;;
    T) TASK="$OPTARG" ;;
    C) COMMUNITY="$OPTARG" ;;
    w) WARNING=$OPTARG ;;
    c) CRITICAL=$OPTARG ;;
    I) INTERFACE=$OPTARG ;;
    l) SEC_LEVEL="$OPTARG" ;;
    u) SEC_NAME="$OPTARG" ;;
    a) AUTH_PROTOCOL="$OPTARG" ;;
    A) AUTH_PASSWORD="$OPTARG" ;;
    x) PRIV_PROTOCOL="$OPTARG" ;;
    X) PRIV_PASSWORD="$OPTARG" ;;
    h) print_help; exit $STATE_UNKNOWN ;;
    V) print_version; exit $STATE_UNKNOWN ;;
  esac
done

# Check for SNMPv3 mandatory parameters
if [ "$SNMP_VERSION" == "3" ]; then
  if [ -z "$SEC_LEVEL" ] || [ -z "$SEC_NAME" ] || [ -z "$AUTH_PROTOCOL" ] || [ -z "$AUTH_PASSWORD" ] || [ -z "$PRIV_PROTOCOL" ] || [ -z "$PRIV_PASSWORD" ]; then
    echo "For SNMPv3, -l secLevel, -u secName, -a authProtocol, -A authPassword, -x privProtocol, and -X privPassword are mandatory."
    exit $STATE_UNKNOWN
  fi
fi

if [ "$TASK" == "memory" ]; then
  TOTALMEMORY=$(snmp_get_value "$OID_MEMORYTOTAL")
  FREEMEMORY=$(snmp_get_value "$OID_MEMORYFREE")

  if [ -n "$TOTALMEMORY" ] && [ -n "$FREEMEMORY" ]; then
    USEDMEMORY=$((TOTALMEMORY - FREEMEMORY))
    USEDMEMORY_POURCENT=$((USEDMEMORY * 100 / TOTALMEMORY))

    if [ "$USEDMEMORY_POURCENT" -gt "$CRITICAL" ]; then
      STATE=$STATE_CRITICAL
    elif [ "$USEDMEMORY_POURCENT" -gt "$WARNING" ]; then
      STATE=$STATE_WARNING
    else
      STATE=$STATE_OK
    fi
    # Results are in Kilobytes, make it human-readable
    USEDMEMORY_FORMAT=$(size_convert "$USEDMEMORY")
    FREEMEMORY_FORMAT=$(size_convert "$FREEMEMORY")
    TOTALMEMORY_FORMAT=$(size_convert "$TOTALMEMORY")

    DESCRIPTION="Memory usage : $USEDMEMORY_FORMAT used for a total of $TOTALMEMORY_FORMAT (${USEDMEMORY_POURCENT}%)"
    DESCRIPTION="${DESCRIPTION}| used=${USEDMEMORY}KB;${WARNING}%;${CRITICAL}%;0"

  else
    echo "Values may not be NULL"
    exit $STATE_UNKNOWN
  fi
fi

if [ "$TASK" == "cpu" ]; then
  CPULOAD5S=$(snmp_get_value "$OID_CPULOAD5S")
  CPULOAD60S=$(snmp_get_value "$OID_CPULOAD60S")
  CPULOAD300S=$(snmp_get_value "$OID_CPULOAD300S")

  if [ "$CPULOAD5S" -gt "$CRITICAL" ] || [ "$CPULOAD60S" -gt "$CRITICAL" ] || [ "$CPULOAD300S" -gt "$CRITICAL" ]; then
    STATE=$STATE_CRITICAL
  elif [ "$CPULOAD5S" -gt "$WARNING" ] || [ "$CPULOAD60S" -gt "$WARNING" ] || [ "$CPULOAD300S" -gt "$WARNING" ]; then
    STATE=$STATE_WARNING
  else
    STATE=$STATE_OK
  fi

  DESCRIPTION="CPU Load : $CPULOAD5S%, $CPULOAD60S%, $CPULOAD300S% | cpu_load_current=$CPULOAD5S;$WARNING;$CRITICAL;0 cpu_load_average60S=$CPULOAD60S;$WARNING;$CRITICAL;0 cpu_load_average300S=$CPULOAD300S;$WARNING;$CRITICAL;0"
fi

if [ "$TASK" == "temperature" ]; then
  TEMP=$(snmp_get_value "$OID_TEMP")
  TEMPMIN=$(snmp_get_value "$OID_TEMPMIN")
  TEMPMAX=$(snmp_get_value "$OID_TEMPMAX")

  if [ "$TEMP" -gt "$CRITICAL" ]; then
    STATE=$STATE_CRITICAL
  elif [ "$TEMP" -gt "$WARNING" ]; then
    STATE=$STATE_WARNING
  else
    STATE=$STATE_OK
  fi

  DESCRIPTION="Temperature : $TEMP°C | temperature=$TEMP;$WARNING;$CRITICAL;0"
fi

if [ "$TASK" == "vpn" ]; then
  STATE=$STATE_UNKNOWN
  CONNS=$(snmp_get_value "$OID_VPN_CONNECTIONS")
  STATE=$STATE_OK
  DESCRIPTION="VPN Connections : OK | vpn_connections=$CONNS;$WARNING;$CRITICAL;0"
fi

check_wan_connection() {
  local connection_name="$1"

  # Base SNMP command with version check
  local snmp_cmd="$CMD_SNMPWALK -t 2 -r 2 -v $SNMP_VERSION"

  # Add SNMPv3 specific parameters if version 3 is selected
  if [ "$SNMP_VERSION" == "3" ]; then
    snmp_cmd="$snmp_cmd -l $SEC_LEVEL -u $SEC_NAME -a $AUTH_PROTOCOL -A $AUTH_PASSWORD -x $PRIV_PROTOCOL -X $PRIV_PASSWORD"
  else
    snmp_cmd="$snmp_cmd -c $COMMUNITY"
  fi

  # Perform SNMP walk to get the connection entries and statuses using the LCOS-MIB
  local conn_entries
  conn_entries=$($snmp_cmd $HOSTNAME -m LCOS-MIB "1.3.6.1.4.1.2356.11.1.14")

  # Determine the channel associated with the specified connection name
  local channel_oid=""
  local channel_id=""
  while read -r line; do
    if echo "$line" | grep -q "$connection_name"; then
      channel_oid=$(echo "$line" | $CMD_AWK '{print $1}')
      channel_id=$(echo "$channel_oid" | awk -F'.' '{print $NF}')
      break
    fi
  done <<< "$conn_entries"

  # Check if channel_id was found
  if [ -z "$channel_id" ]; then
    echo "WAN Connection: UNKNOWN - Connection name '$connection_name' not found"
    exit $STATE_UNKNOWN
  fi

  # OID to check connection status
  local conn_status_oid="LCOS-MIB::lcsStatusInfoConnectionEntryStatus.$channel_id"
  local conn_status
  conn_status=$($snmp_cmd $HOSTNAME "$conn_status_oid" | $CMD_AWK '{ print $4 }')

  if [ "$conn_status" != "Connection" ]; then
    echo "WAN Connection: CRITICAL - '$connection_name' is not connected"
    exit $STATE_CRITICAL
  fi

  # Get RX/TX per second and average for the identified channel
  local rx_current_oid="LCOS-MIB::lcsStatusWanThroughputEntryRxSCurrent.$channel_id"
  local tx_current_oid="LCOS-MIB::lcsStatusWanThroughputEntryTxSCurrent.$channel_id"
  local rx_avg_oid="LCOS-MIB::lcsStatusWanThroughputEntryRxSAverage.$channel_id"
  local tx_avg_oid="LCOS-MIB::lcsStatusWanThroughputEntryTxSAverage.$channel_id"

  local rx_current
  local tx_current
  local rx_avg
  local tx_avg

  rx_current=$($snmp_cmd $HOSTNAME "$rx_current_oid" | $CMD_AWK '{ print $4 }')
  tx_current=$($snmp_cmd $HOSTNAME "$tx_current_oid" | $CMD_AWK '{ print $4 }')
  rx_avg=$($snmp_cmd $HOSTNAME "$rx_avg_oid" | $CMD_AWK '{ print $4 }')
  tx_avg=$($snmp_cmd $HOSTNAME "$tx_avg_oid" | $CMD_AWK '{ print $4 }')

  # Construct the output with metrics
  echo -n "WAN Connection: OK - '$connection_name' is connected"
  echo "| rx_current=${rx_current}bps tx_current=${tx_current}bps rx_avg=${rx_avg}bps tx_avg=${tx_avg}bps"

  exit $STATE_OK
}

# Adding the check for the wan task
if [ "$TASK" == "wan" ]; then
  check_wan_connection "$INTERFACE"
fi

echo "$DESCRIPTION"
exit $STATE

