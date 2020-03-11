#!/bin/bash
 
#*********************************************************************
#       Configuration WAN-PC and WAN-FON failover
#*********************************************************************
LOGFILE="/var/log/failover.log"                        # Logfile
TELEGRAMFILE="/var/log/failover-telegram.log"          # Logfile
DEF_PC_GATEWAY="13.18.11.1"      # Default WAN-PC Gateway
DEF_FON_GATEWAY="192.168.2.1"	  # Default WAN-FON Gateway
BCK_PC_GATEWAY="192.168.2.1"         # Backup Gateway
BCK_FON_GATEWAY="13.18.11.1"      # Backup Fon Gateway
DEF_FON_ROUTE="uplink2"            # Default iproute
BCK_FON_ROUTE="uplink1"            # Backup iproute
SOURCE_IP_FON="10.13.38.0/24"        # FON IP Source
RMT_IP_1="8.8.4.4"          	# first remote ip
RMT_IP_2="8.8.8.8"              # second remote ip
PING_TIMEOUT="1"                # Ping timeout in seconds
DEF_FON_DEVICE_GW="enp0s31f6"   # Default Phone Gateway device for Ping
#*********************************************************************
# check user is root
if [ `whoami` != "root" ]
then
        echo "Failover script must be run as root!" | tee $LOGFILE 
        exit 1
fi
#*************************************************
#      1. Check WAN-PC connection
#*************************************************
# check gateway
CURRENT_GW=`ip route show | grep default | awk '{ print $3 }'`
if [ "$CURRENT_GW" == "$DEF_PC_GATEWAY" ]
then
        ping -c 2 -W $PING_TIMEOUT $RMT_IP_1 > /dev/null
        PING_1=$?
else
        # add static routes to remote ip's
        ip route add $RMT_IP_1 via $DEF_PC_GATEWAY
        ping -c 2 -W $PING_TIMEOUT $RMT_IP_1 > /dev/null
        PING_1=$?
        # del static route to remote ip's
        ip route del $RMT_IP_1
fi

echo $PING_1
echo $PING_2
 
LOG_TIME=`date +%b' '%d' '%T`

if [ "$PING_1" == "1" ]
then
        if [ "$CURRENT_GW" == "$DEF_PC_GATEWAY" ]
        then
                ip route del default
                ip route add default via $BCK_PC_GATEWAY
                # flushing routing cache
                ip route flush cache
                echo "$LOG_TIME: $0 - switched PC Gateway to Backup with IP $BCK_PC_GATEWAY" | tee -a $LOGFILE  
		echo "_LoadBalancer_ - switched *PC Gateway* to *Backup* - *$BCK_PC_GATEWAY*" | tee -a $TELEGRAMFILE
        fi
 
elif [ "$CURRENT_GW" != "$DEF_PC_GATEWAY" ]
then
        # switching to default
        ip route del default
        ip route add default via $DEF_PC_GATEWAY
        ip route flush cache
        echo "$LOG_TIME: $0 - PC Gateway switched to Default with IP $DEF_PC_GATEWAY"  | tee -a $LOGFILE
	echo " _LoadBalancer_ - switched *PC Gateway* back to *Default* - *$DEF_PC_GATEWAY*"| tee -a $TELEGRAMFILE
fi


#*************************************************
#      2. Check WAN-FON connection
#*************************************************
# check gateway
#
# The following is important on FON DEFAULT GATEWAY and PC DEFAULT GATEWAY
#ip route add default via $BCK_FON_GATEWAY table uplink1
#ip route add default via $DEF_FON_GATEWAY table uplink2


CURRENT_ROUTE=`ip rule show | grep $SOURCE_IP_FON | awk '{ print $5 }'`
# add static routes to remote ip's
ip route add $RMT_IP_1 via $DEF_FON_GATEWAY
ping -c 2 -W $PING_TIMEOUT $RMT_IP_1 > /dev/null
PING_1=$?
# del static route to remote ip's
ip route del $RMT_IP_1




LOG_TIME=`date +%b' '%d' '%T`

if [ "$PING_1" == "1" ]
then
        if [ "$CURRENT_ROUTE" == "$DEF_FON_ROUTE" ]
        then
		ip rule delete table $DEF_FON_ROUTE
		ip rule add from $SOURCE_IP_FON table $BCK_FON_ROUTE
                # flushing routing cache
                ip route flush cache
                echo "$LOG_TIME: $0 - switched FON Gateway to Backup with IP $BCK_FON_GATEWAY" | tee -a $LOGFILE
		echo "_LoadBalancer_ - switched *FON Gateway* to *Backup* - *$BCK_FON_GATEWAY*" |tee -a $TELEGRAMFILE 
        fi
 
elif [ "$CURRENT_ROUTE" != "$DEF_FON_ROUTE" ]
then
        # switching to default
	ip rule delete table $BCK_FON_ROUTE
	ip rule add from $SOURCE_IP_FON table $DEF_FON_ROUTE
        ip route flush cache
        echo "$LOG_TIME: $0 - FON Gateway switched to Default  with IP $DEF_FON_GATEWAY" | tee -a $LOGFILE 
	echo " _LoadBalancer_ - switched *FON Gateway* back to *Default* - *$DEF_FON_GATEWAY*" | tee -a $TELEGRAMFILE
fi

sleep 30 

if [ -f $TELEGRAMFILE ]; then
        while read -r LINE || [[ -n $LINE ]]; do
		if [ -z "$LINE" ]
		then
      			echo "\$LINE is empty"
		else
      			echo "\$LINE is NOT empty"
		
                	curl -s -X POST https://api.telegram.org/bot_token/sendMessage -d chat_id=-1337133713370 -d text="$LINE"
			/root/loadbalancer_discord.sh --webhook-url=https://discordapp.com/api/webhooks/webhook_id --text "Notify" --description "$LINE" --footer "Date/Time" --timestamp --title "WAN is changing" --color "0xFF0000"
			sleep 1
		fi
        done <$TELEGRAMFILE
        echo "" | tee $TELEGRAMFILE
else
        echo "file not found"


fi
