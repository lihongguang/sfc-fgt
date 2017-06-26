#!/bin/bash

ifconfig eth1 up;
ifconfig eth2 up;
apt-get install -y python3-pip
pip3 install hexdump

pkill proxy
pkill tcpdump

nohup  tcpdump -i eth1 -l >/dev/null &

nohup tcpdump -i eth2 -l >/dev/null &

nohup /vagrant/proxy.py --encap_if eth0 --unencap_in_if eth2 --unencap_out_if eth1 2>&1 >proxy.log &