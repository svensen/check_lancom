#!/bin/bash

# check_lancom
# Description : Checks LANCOM Router

# MIT License
#
# Copyright (c) 2017 Dennis Michalski
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


# Commands
CMD_BASENAME="$(which basename)"
CMD_SNMPGET="$(which snmpget)"
CMD_SNMPWALK="$(which snmpwalk)"
CMD_SNMPTABLE="$(which snmptable)"
CMD_AWK="$(which awk)"
CMD_GREP="$(which grep)"
CMD_BC="$(which bc)"
CMD_EXPR="$(which expr)"

# Script name
SCRIPTNAME=`$CMD_BASENAME $0`

# Version
VERSION="1.0"

# Plugin return codes
STATE_OK=0
STATE_WARNING=1
STATE_CRITICAL=2
STATE_UNKNOWN=3
STATE_CONNECTED="eConnection(7)"

#Memory
OID_MEMORYTOTAL="LCOS-MIB::lcsStatusHardwareInfoTotalMemoryKbytes"
OID_MEMORYFREE="LCOS-MIB::lcsStatusHardwareInfoFreeMemoryKbytes"

#CPU
OID_CPULOAD="LCOS-MIB::lcsStatusHardwareInfoCpuLoadPercent"
OID_CPULOAD5S="LCOS-MIB::lcsStatusHardwareInfoCpuLoad5sPercent"
OID_CPULOAD60S="LCOS-MIB::lcsStatusHardwareInfoCpuLoad60sPercent"
OID_CPULOAD300S="LCOS-MIB::lcsStatusHardwareInfoCpuLoad300sPercent"

#Temperature
OID_TEMP="LCOS-MIB::lcsStatusHardwareInfoTemperatureDegrees"
OID_TEMPMAX="LCOS-MIB::lcsSetupTemperatureMonitorUpperLimitDegrees"
OID_TEMPMIN="LCOS-MIB::lcsSetupTemperatureMonitorLowerLimitDegrees"

#VPN Connections
OID_VPN_CONNECTIONS="LCOS-MIB::lcsStatusVpnConnectionsEntryState"

# WAN Througput
OID_WAN_IF_THROUGHPUT="LCOS-MIB::lcsStatusWanThroughputTable"

# Default variables
DESCRIPTION="Unknown"
STATE=$STATE_UNKNOWN

# Default options
COMMUNITY="public"
HOSTNAME="192.168.10.1"
TASK=""
WARNING=60
CRITICAL=65
INTERFACE=eVdsl1

# Option processing
print_usage() {
  echo "Usage: ./check_lancom -H 192.168.0.1 -T traffic -C public -w 60 -c 65 -I eVdsl1"
  echo "  $SCRIPTNAME -H ADDRESS"
  echo "  $SCRIPTNAME -C STRING"
  echo "  $SCRIPTNAME -w INTEGER"
  echo "  $SCRIPTNAME -c INTEGER"
  echo "  $SCRIPTNAME -I STRING"
  echo "  $SCRIPTNAME -h"
  echo "  $SCRIPTNAME -V"
}

print_version() {
  echo $SCRIPTNAME version $VERSION
  echo ""
  echo "This nagios plugin comes with ABSOLUTELY NO WARRANTY."
  echo "You may redistribute copies of the plugin under the terms of the MIT License."}
}

print_help() {
  print_version
  echo ""
  print_usage
  echo ""
  echo "Checks Lancom Router"
  echo ""
  echo "-H ADDRESS"
  echo "   Name or IP address of host (default: 192.168.0.1)"
  echo "-T TASK"
  echo "   Task to check. Must be in: temperature, cpu, memory, traffic"
  echo "-C STRING"
  echo "   Community name for the host SNMP agent (default: public)"
  echo "-w INTEGER"
  echo "   Warning level for memory usage in percent (default: 60)"
  echo "-c INTEGER"
  echo "   Critical level for memory usage in percent (default: 65)"
  echo "-I INTEGER"
  echo "   Interface to monitor traffic for (default: eVdsl1)"
  echo "-h"
  echo "   Print this help screen"
  echo "-V"
  echo "   Print version and license information"
  echo ""
  echo ""
}

# Plugin processing
size_convert() {
  if [ $VALUE -ge  1073741824 ]; then
    VALUE=`echo "scale=2 ; ( ( $VALUE / 1024 ) / 1024 ) / 1024" | $CMD_BC`
    VALUE="$VALUE GB"
  elif [ $VALUE -ge 1048576 ]; then
    VALUE=`echo "scale=2 ; ( $VALUE / 1024 ) / 1024" | $CMD_BC`
    VALUE="$VALUE MB"
  elif [ $VALUE -ge 1024 ]; then
    VALUE=`echo "scale=2 ; $VALUE / 1024" | $CMD_BC`
    VALUE="$VALUE KB"
  else
    VALUE="$VALUE Octets"
  fi
}

while getopts H:T:C:w:c:I:hV OPT
do
  case $OPT in
    H) HOSTNAME="$OPTARG" ;;
	T) TASK="$OPTARG" ;;
    C) COMMUNITY="$OPTARG" ;;
    w) WARNING=$OPTARG ;;
    c) CRITICAL=$OPTARG ;;
    I) INTERFACE=$OPTARG ;;
    h)
      print_help
      exit $STATE_UNKNOWN
      ;;
    V)
      print_version
      exit $STATE_UNKNOWN
      ;;
   esac
done

if [ "$TASK" == "memory" ]; then
	# Get memory usage from router
	TOTALMEMORY=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_MEMORYTOTAL | $CMD_AWK '{ print $4}'`
	FREEMEMORY=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_MEMORYFREE | $CMD_AWK '{ print $4}'`

	# Process data
	if [ -n "$TOTALMEMORY" ] && [ -n "$FREEMEMORY" ]; then
	  # calculate usage
	  USEDMEMORY=`$CMD_EXPR \( $TOTALMEMORY - $FREEMEMORY \)`
	  USEDMEMORY_POURCENT=`$CMD_EXPR \( $USEDMEMORY \* 100 \) / $TOTALMEMORY`

	  if [ $WARNING != 0 ] || [ $CRITICAL != 0 ]; then
		PERFDATA_WARNING=`$CMD_EXPR \( $TOTALMEMORY \* $WARNING \) / 100`
		PERFDATA_CRITICAL=`$CMD_EXPR \( $TOTALMEMORY \* $CRITICAL \) / 100`
		if [ $USEDMEMORY_POURCENT -gt $CRITICAL ] && [ $CRITICAL != 0 ]; then
		  STATE=$STATE_CRITICAL
		elif [ $USEDMEMORY_POURCENT -gt $WARNING ] && [ $WARNING != 0 ]; then
		  STATE=$STATE_WARNING
		else
		  STATE=$STATE_OK
		fi

		VALUE=$USEDMEMORY
		size_convert
		USEDMEMORY_FORMAT=$VALUE

		VALUE=$FREEMEMORY
		size_convert
		FREEMEMORY_FORMAT=$VALUE

		VALUE=$TOTALMEMORY
		size_convert
		TOTALMEMORY_FORMAT=$VALUE

		DESCRIPTION="Memory usage : $USEDMEMORY_FORMAT used for a total of $TOTALMEMORY_FORMAT (${USEDMEMORY_POURCENT}%)"
		DESCRIPTION="${DESCRIPTION}| used=${USEDMEMORY}B;$PERFDATA_WARNING;$PERFDATA_CRITICAL;0"

	  else
		echo "Values not allowed"
		exit $STATE_UNKNOWN
	  fi
	else
	  echo "Values may not be NULL"
	  exit $STATE_UNKNOWN
	fi
fi

if [ "$TASK" == "cpu" ]; then
	# Get CPU Load in Percent
	CPULOAD5S=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_CPULOAD5S | $CMD_AWK '{ print $4 }'`
	CPULOAD60S=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_CPULOAD60S | $CMD_AWK '{ print $4 }'`
	CPULOAD300S=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_CPULOAD300S | $CMD_AWK '{ print $4 }'`
	CPULOAD=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_CPULOAD | $CMD_AWK '{ print $4 }'`

	if [ $WARNING != 0 ] || [ $CRITICAL != 0 ]; then
	  if [ $CPULOAD5S -gt $CRITICAL ] && [ $CRITICAL != 0 ]; then
		STATE=$STATE_CRITICAL
	  elif [ $CPULOAD60S -gt $CRITICAL ] && [ $CRITICAL != 0 ]; then
		STATE=$STATE_CRITICAL
	  elif [ $CPULOAD300S -gt $CRITICAL ] && [ $CRITICAL != 0 ]; then
		STATE=$STATE_CRITICAL
	  elif [ $CPULOAD5S -gt $WARNING ] && [ $WARNING != 0 ]; then
		STATE=$STATE_WARNING
	  elif [ $CPULOAD60S -gt $WARNING ] && [ $WARNING != 0 ]; then
		STATE=$STATE_WARNING
	  elif [ $CPULOAD300S -gt $WARNING ] && [ $WARNING != 0 ]; then
		STATE=$STATE_WARNING
	  else
		STATE=$STATE_OK
	  fi
	fi

	DESCRIPTION="CPU Load : $CPULOAD5S%, $CPULOAD60S%, $CPULOAD300S% | cpu_load_current=$CPULOAD;$WARNING;$CRITICAL;0 cpu_load_average5S=$CPULOAD5S;$WARNING;$CRITICAL;0 cpu_load_average60S=$CPULOAD60S;$WARNING;$CRITICAL;0 cpu_load_average300S=$CPULOAD300S;$WARNING;$CRITICAL;0"
fi

if [ "$TASK" == "temperature" ]; then
	# Get Temperature in degrees Celsius
	TEMP=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_TEMP | $CMD_AWK '{ print $4 }'`
	TEMPMIN=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_TEMPMIN | $CMD_AWK '{ print $4 }'`
	TEMPMAX=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_TEMPMAX | $CMD_AWK '{ print $4 }'`

	if [ $WARNING -gt $TEMPMAX ] || [ $CRITICAL -gt $TEMPMAX ]; then
	  echo "Value not allowed"
	  exit $STATE_UNKNOWN
	fi

	if [ $WARNING != 0 ] || [ $CRITICAL != 0 ]; then
	  if [ $TEMP -gt $WARNING ] && [ $WARNING != 0 ]; then
		STATE=$STATE_WARNING
	  elif [ $TEMP -gt $CRITICAL ] && [ $CRITICAL != 0 ]; then
		STATE=$STATE_CRITICAL
	  else
		STATE=$STATE_OK
	  fi
	fi
	DESCRIPTION="Temperature : $TEMP°C | temperature=$TEMP;$WARNING;$CRITICAL;0"
fi

if [ "$TASK" == "vpn" ]; then
        ERROR_CONNS=""
        STATE=$STATE_UNKNOWN
        CONNS=`$CMD_SNMPWALK -t 2 -r 2 -v 1 -c $COMMUNITY $HOSTNAME $OID_VPN_CONNECTIONS`
        while read -r line; do
            VALUE=`$CMD_AWK -F" " '{ print $4 }' <<< "$line"`
            CONN_NAME=`$CMD_AWK -F" " '{ print $1 }' <<< "$line"`
            CONN_NAME=`$CMD_AWK -F" " '{ split($0,a,"."); print a[2]; }' <<< "$CONN_NAME"`
            if [ $VALUE != $STATE_CONNECTED ]; then
                ERROR_CONNS="$ERROR_CONNS $CONN_NAME"
                STATE=$STATE_CRITICAL
                DESCRIPTION="VPN Connections : Critical. The following conenctions are not in State Connected: $ERROR_CONNS"
            fi
        done <<< "$CONNS"
        if [ $STATE != $STATE_CRITICAL ]; then
            STATE=$STATE_OK
            DESCRIPTION="VPN Connections : OK"
        fi
        #echo $CONNS
fi


echo $DESCRIPTION
exit $STATE