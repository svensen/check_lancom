# check_lancom
Shell Script for monitoring LANCOM devices via Nagios.

The script is loosely based on the work of Roland Rickborn who published some similar scripts under <https://github.com/exensio/lancom-router-nagios-plugin>.

## Usage
This script comes as all-in-one variant. At the moment the following stats can be obtained:
1. Memory Usage
2. CPU Usage
3. System Temperature
4. Status of VPN connections

Usage examples:
```
check_lancom.sh -H 192.168.10.1 -T memory -C public -w 90 -c 95
check_lancom.sh -H 192.168.10.1 -T cpu -C public -w 90 -c 95
check_lancom.sh -H 192.168.10.1 -T temperature -C public -w 60 -c 65
check_lancom.sh -H 192.168.10.1 -T vpn -C public