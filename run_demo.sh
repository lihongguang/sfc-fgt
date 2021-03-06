#!/bin/bash

#************************************************
# Service Function Chain demo with Fortigate
#   _____ ______ _____            _ _   _
#  / ____|  ____/ ____|          (_) | | |
# | (___ | |__ | |      __      ___| |_| |__
#  \___ \|  __|| |      \ \ /\ / / | __| '_ \
#  ____) | |   | |____   \ V  V /| | |_| | | |
# |_____/|_|    \_____|   \_/\_/ |_|\__|_| |_|
#  ______         _   _  _____       _
# |  ____|       | | (_)/ ____|     | |
# | |__ ___  _ __| |_ _| |  __  __ _| |_ ___
# |  __/ _ \| '__| __| | | |_ |/ _` | __/ _ \
# | | | (_) | |  | |_| | |__| | (_| | ||  __/
# |_|  \___/|_|   \__|_|\_____|\__,_|\__\___|
#
#
# Use: ./run_demo.sh <location_of_fortigate_vm>
#
# See README.md
#
# Miguel Angel Muñoz Gonzalez
# magonzalez(at)fortinet.com
#
# Took ideas from opendaylight/sfc project
#************************************************
set -x

source env.sh

#************************************************
# Check Fortigate VM existence
#************************************************

if [ -z "$1" ]; then
  echo "Need location of Fortigate image"
  exit -1
fi
result=$(file $1)
if [[ $result == *"QEMU QCOW Image (v2)"* ]]; then
   echo "Supplied Fortigate image is in: $1"
   FORTIGATE_QCOW2=$1
else
   echo "Supplied Fortigate image does not look a qcow2 file"
   exit -1
fi
if [[ "$(realpath $FORTIGATE_QCOW2)" == "$(pwd)/fortios.qcow2" ]]; then
   echo "FortiGate image can not be named fortios.qcow2 in this directory. Choose different location/name"
   exit -1
fi

#************************************************
# Get OpenDayLight
#************************************************

if [ ! -e karaf-0.7.0.tar.gz ]; then
  wget https://nexus.opendaylight.org/content/repositories/public/org/opendaylight/integration/karaf/0.7.0/karaf-0.7.0.tar.gz
fi
rm -rf karaf-0.7.0/
tar xvfz karaf-0.7.0.tar.gz
cp karaf karaf-0.7.0/

xterm -geometry 110x25+650+300 -e "cd ${PWD}/karaf-0.7.0/ && ./karaf" &
sleep 5

#************************************************
# Clean previous executions
#************************************************

./cleanup_demo.sh

#************************************************
# Get SFC Proxy
#************************************************

rm -f proxy.py
wget https://raw.githubusercontent.com/fortinet-tigers/sfc-proxy/master/proxy.py
chmod 777 proxy.py

#************************************************
# Ensure there is a generated public key
#************************************************

if [ ! -f ${HOME}/.ssh/id_rsa.pub ]; then 
  echo "Need ${HOME}/.ssh/id_rsa.pub generated. Do ssh-keygen"
  exit -1
fi

#************************************************
# Check existence of previous image with OVS compiled
# If not, download base image, trusty 14.04, cloud based
#************************************************

if [ -e ${PREVIOUS_SAVED_IMAGE_NAME} ]; then

   cp ${PREVIOUS_SAVED_IMAGE_NAME} ${CLASSIFIER1_NAME}.img
   SKIP_OVS_COMPILATION=true

else

    if [ ! -e ${UBUNTU_IMAGE_NAME} ]; then

       wget ${UBUNTU_IMAGE_URL}
       qemu-img resize ${UBUNTU_IMAGE_NAME} +1Gb
       if [ $? -ne 0 ] ; then
          echo "Failed to resize ubuntu base image. Exiting..."
          exit -1
       fi
    fi
    cp ${UBUNTU_IMAGE_NAME} ${CLASSIFIER1_NAME}.img

fi

#************************************************
# Set virtual networks with virsh
#************************************************
xterm -geometry 70x25+1400+40 -fg yellow -e watch virsh net-list --all &

cat >virbr1 <<EOF
<network>
  <name>virbr1</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr1' stp='on' delay='0'/>
  <mac address='52:54:00:79:7c:c3'/>
  <ip address='192.168.60.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.60.2' end='192.168.60.254'/>
      <host mac='${CLASSIFIER1_MAC}' name='${CLASSIFIER1_NAME}' ip='${CLASSIFIER1_IP}'/>
      <host mac='${CLASSIFIER2_MAC}' name='${CLASSIFIER2_NAME}' ip='${CLASSIFIER2_IP}'/>
      <host mac='${SFF1_MAC}' name='${SFF1_NAME}' ip='${SFF1_IP}'/>
      <host mac='${SFF2_MAC}' name='${SFF2_NAME}' ip='${SFF2_IP}'/>
      <host mac='${SF1_MAC}' name='${SF1_NAME}' ip='${SF1_IP}'/>
      <host mac='${SF2_PROXY_MAC}' name='${SF2_PROXY_NAME}' ip='${SF2_PROXY_IP}'/>
      <host mac='${SF3_PROXY_MAC}' name='${SF3_PROXY_NAME}' ip='${SF3_PROXY_IP}'/>
    </dhcp>
  </ip>
</network>
EOF

cat >virbr2 <<EOF
<network>
  <name>virbr2</name>
  <bridge name='virbr2' stp='off' delay='0' />
  <mac address='52:54:00:79:7c:c4'/>
  <host mac='${SF2_MAC}' ip='${SF2_IP}'/>
  <host mac='${SF2_PROXY_MAC2}' ip='${SF2_PROXY_IP2}'/>
</network>
EOF

cat >virbr3 <<EOF
<network>
  <name>virbr3</name>
  <bridge name='virbr3' stp='off' delay='0' />
  <mac address='52:54:00:79:7c:c5'/>
  <host mac='${SF2_MAC2}' ip='${SF2_IP2}'/>
  <host mac='${SF2_PROXY_MAC3}' ip='${SF2_PROXY_IP3}'/>
</network>
EOF

cat >virbr4 <<EOF
<network>
  <name>virbr4</name>
  <bridge name='virbr4' stp='off' delay='0' />
  <mac address='52:54:00:79:7c:c6'/>
  <host mac='${SF3_MAC}' ip='${SF3_IP}'/>
  <host mac='${SF3_PROXY_MAC2}' ip='${SF3_PROXY_IP2}'/>
</network>
EOF

cat >virbr5 <<EOF
<network>
  <name>virbr5</name>
  <bridge name='virbr5' stp='off' delay='0' />
  <mac address='52:54:00:79:7c:c7'/>
  <host mac='${SF3_MAC2}' ip='${SF3_IP2}'/>
  <host mac='${SF3_PROXY_MAC3}' ip='${SF3_PROXY_IP3}'/>
</network>
EOF

sudo virsh net-create virbr1
sudo virsh net-create virbr2
sudo virsh net-create virbr3
sudo virsh net-create virbr4
sudo virsh net-create virbr5


#************************************************
# Prepare Cloud Init for first VM
#************************************************

xterm -geometry 70x25+1400+550 -fg yellow -e watch virsh list --all &

cat >meta-data <<EOF
instance-id: ${CLASSIFIER1_NAME}
local-hostname: ${CLASSIFIER1_NAME}
EOF

#Note password is always 'm'

cat >user-data <<EOF
#cloud-config
users:
  - name: ${USER}
    gecos: Host User Replicated
    passwd: \$1\$xyz\$Ilzr7fdQW.frxCgmgIgVL0
    ssh-authorized-keys:
      - $(cat ${HOME}/.ssh/id_rsa.pub)
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    inactive: false
    lock_passwd: false
  - name: sfc
    gecos: sfc additional user
    passwd: \$1\$xyz\$Ilzr7fdQW.frxCgmgIgVL0
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    inactive: false
    lock_passwd: false
EOF

rm -rf ${CLASSIFIER1_NAME}-cidata.iso
genisoimage -output ${CLASSIFIER1_NAME}-cidata.iso -volid cidata -joliet -rock user-data meta-data

sudo virt-sysprep -a ${CLASSIFIER1_NAME}.img --root-password password:m \
    --delete /var/lib/cloud/* \
    --firstboot-command 'useradd -m -p "" vagrant ; chage -d 0 vagrant; ssh-keygen -A; rm -rf /var/lib/cloud/*; cloud-init init'

virt-install --connect qemu:///system --noautoconsole --filesystem ${PWD},shared_dir --import --name ${CLASSIFIER1_NAME} --ram 2048 --vcpus 1 --disk ${CLASSIFIER1_NAME}.img,size=3 --disk ${CLASSIFIER1_NAME}-cidata.iso,device=cdrom --network bridge=virbr1,mac=${CLASSIFIER1_MAC}

ssh-keygen -R ${CLASSIFIER1_IP}
alias ssh='ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'

until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo mkdir -p /vagrant/"
do
  sleep 1
  echo "."
done

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo chmod 777 /vagrant/"

rsync -e "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no" -r -v --exclude karaf-0.7.0* --max-size=1048576 ./*  ${CLASSIFIER1_IP}:/vagrant/

#************************************************
# Install OVS on first VM
#************************************************

if [ ! ${SKIP_OVS_COMPILATION} ];then
   ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo /vagrant/ovs/install_ovs.sh"
   if [ $? -ne 0 ] ; then
      echo "Failed to install ovs on ${CLASSIFIER1_NAME}"
      exit -1
   fi
fi

#************************************************
# Ensure ODL renderer is initialized successfully
#************************************************

retries=20
while [ $retries -gt 0 ]
do
    OK=0
    result=$(curl -H "Content-Type: application/json" -H "Cache-Control: no-cache" -X GET --user admin:admin http://${LOCALHOST}:8181/restconf/operational/network-topology:network-topology/)
    OK=$((OK+$?))
    result=$(sshpass -p karaf ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 8101 -l karaf ${LOCALHOST} display | grep "successfully started the SfcOfRenderer")
    OK=$((OK+$?))
    result=$(sshpass -p karaf ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p 8101 -l karaf ${LOCALHOST} display | grep "successfully started the SfcScfOfRenderer")
    OK=$((OK+$?))
    if [ $OK -eq 0 ] ; then
        break
    fi
    echo "Waiting Openflow renderer and classifier initialized..."
    sleep 5
    retries=$((retries-1))
done

if [ $retries -eq 0 ] ; then
    echo "features are not started correctly: ${features}"
    exit -1
fi

#************************************************
# Stop first VM (prior to clone image)
#************************************************

sleep 30
virsh shutdown ${CLASSIFIER1_NAME}

sleep 10

#************************************************
# Copy image with OVS for later reuse
#************************************************

if [ ! ${SKIP_OVS_COMPILATION} ];then
   sudo cp ${CLASSIFIER1_NAME}.img ${PREVIOUS_SAVED_IMAGE_NAME}
fi


#************************************************
# Clone images for the rest of vms
#************************************************

declare -A VM_MAC=( [${CLASSIFIER2_NAME}]=${CLASSIFIER2_MAC} \
   [${SFF1_NAME}]=${SFF1_MAC} \
   [${SFF2_NAME}]=${SFF2_MAC} \
   [${SF1_NAME}]=${SF1_MAC} \
   [${SF2_PROXY_NAME}]=${SF2_PROXY_MAC} \
   [${SF3_PROXY_NAME}]=${SF3_PROXY_MAC})

for VM_NAME in ${!VM_MAC[@]};
do

  echo "Cloning $VM_NAME with MAC: ${VM_MAC[${VM_NAME}]}"

   virt-clone --connect qemu:///system --original ${CLASSIFIER1_NAME} --name ${VM_NAME} --file ${VM_NAME}.img --mac=${VM_MAC[${VM_NAME}]}
   if [ $? -ne 0 ]; then
     echo "Error cloning image. Aborting"
     exit -1
   fi

   sleep 1

   sudo virt-sysprep -a ${VM_NAME}.img --hostname ${VM_NAME} --firstboot-command "sudo ssh-keygen -A;grep ${VM_NAME} /etc/hosts||echo 127.0.0.1 ${VM_NAME} >>/etc/hosts"

   cat >meta-data <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF
   rm -rf ${VM_NAME}-cidata.iso
   genisoimage -output ${VM_NAME}-cidata.iso -volid cidata -joliet -rock user-data meta-data
   chmod 666 ${VM_NAME}-cidata.iso
   virsh change-media ${VM_NAME} hdb --eject --config --force
   virsh change-media ${VM_NAME} hdb ${PWD}/${VM_NAME}-cidata.iso --insert --config --force
done

#************************************************
# Modify etc/hosts also in Classifier1
#************************************************

sudo virt-sysprep -a ${CLASSIFIER1_NAME}.img --hostname ${CLASSIFIER1_NAME} --firstboot-command "ssh-keygen -A; rm -rf /var/lib/cloud/*; cloud-init init;grep ${CLASSIFIER1_NAME} /etc/hosts||echo 127.0.0.1 ${CLASSIFIER1_NAME} >>/etc/hosts"

#************************************************
# Start everything up
#************************************************

VMs="${SF2_PROXY_NAME} \
   ${SF3_PROXY_NAME} \
   ${SF1_NAME} \
   ${SFF2_NAME} \
   ${SFF1_NAME} \
   ${CLASSIFIER2_NAME} \
   ${CLASSIFIER1_NAME}"

for VM_NAME in $VMs;
do
 virsh start $VM_NAME
 sleep 1
done

#************************************************
# Start FGT-VM
#************************************************

rm -f fortios.qcow2
rm -rf cfg-drv-fgt
rm -rf ${SF2_NAME}-cidata.iso

cp ${FORTIGATE_QCOW2} ./fortios.qcow2

mkdir -p cfg-drv-fgt/openstack/latest/
mkdir -p cfg-drv-fgt/openstack/content/

cat >cfg-drv-fgt/openstack/content/0000 <<EOF
-----BEGIN FGT VM LICENSE-----
<empty....fill your own!>
-----END FGT VM LICENSE-----
EOF

cat >cfg-drv-fgt/openstack/latest/user_data <<EOF
config system interface
edit "port1"
set ip 192.168.122.40/24
next
end
config system virtual-wire-pair
    edit "vwp1"
        set member "port2" "port3"
    next
end
config firewall policy
    edit 1
        set name "vwp1-policy"
        set srcintf "port2" "port3"
        set dstintf "port2" "port3"
        set srcaddr "all"
        set dstaddr "all"
        set action accept
        set schedule "always"
        set service "ALL"
        set logtraffic disable
    next
end

EOF

sudo mkisofs -publisher "OpenStack Nova 12.0.2" -J -R -V config-2 -o ${SF2_NAME}-cidata.iso cfg-drv-fgt
virt-install --connect qemu:///system --noautoconsole --filesystem ${PWD},shared_dir --import --name ${SF2_NAME} --ram 1024 --vcpus 1 --disk fortios.qcow2,size=3 --disk fgt-logs.qcow2,size=30 --disk ${SF2_NAME}-cidata.iso,device=cdrom,bus=ide,format=raw,cache=none --network bridge=virbr0,mac=${SF2_MAC_ADMIN},model=virtio --network bridge=virbr2,mac=${SF2_MAC},model=virtio --network bridge=virbr3,mac=${SF2_MAC2},model=virtio

sleep 5

#************************************************
# Start Second FGT-VM
#************************************************

rm -f fortios2.qcow2
rm -rf cfg-drv-fgt2
rm -rf ${SF3_NAME}-cidata.iso

cp ${FORTIGATE_QCOW2} ./fortios2.qcow2

mkdir -p cfg-drv-fgt2/openstack/latest/
mkdir -p cfg-drv-fgt2/openstack/content/

cat >cfg-drv-fgt2/openstack/content/0000 <<EOF
-----BEGIN FGT VM LICENSE-----
<empty....fill your own!>
-----END FGT VM LICENSE-----
EOF

cat >cfg-drv-fgt2/openstack/latest/user_data <<EOF
config system interface
   edit "port1"
      set ip 192.168.122.80/24
   next
   edit "port2"
      set mtu-override enable
      set mtu 1400
   next
   edit "port3"
      set mtu-override enable
      set mtu 1400
   next
end
config system virtual-wire-pair
    edit "vwp1"
        set member "port2" "port3"
    next
end
config firewall policy
    edit 1
        set name "vwp1-policy"
        set srcintf "port2" "port3"
        set dstintf "port2" "port3"
        set srcaddr "all"
        set dstaddr "all"
        set action accept
        set schedule "always"
        set service "ALL"
        set logtraffic disable
    next
end

EOF

sudo mkisofs -publisher "OpenStack Nova 12.0.2" -J -R -V config-2 -o ${SF3_NAME}-cidata.iso cfg-drv-fgt2
virt-install --connect qemu:///system --noautoconsole --filesystem ${PWD},shared_dir --import --name ${SF3_NAME} --ram 1024 --vcpus 1 --disk fortios2.qcow2,size=3 --disk fgt-logs2.qcow2,size=30 --disk ${SF3_NAME}-cidata.iso,device=cdrom,bus=ide,format=raw,cache=none --network bridge=virbr0,mac=${SF3_MAC_ADMIN},model=virtio --network bridge=virbr4,mac=${SF3_MAC},model=virtio --network bridge=virbr5,mac=${SF3_MAC2},model=virtio

sleep 5

#************************************************
# Add two more interfaces to SF2_PROXY
#************************************************

virsh attach-interface --domain ${SF2_PROXY_NAME} --type network \
        --source virbr2 \
        --mac ${SF2_PROXY_MAC2} --config --live

virsh attach-interface --domain ${SF2_PROXY_NAME} --type network \
        --source virbr3 \
        --mac ${SF2_PROXY_MAC3} --config --live


#************************************************
# Add two more interfaces to SF3_PROXY
#************************************************

virsh attach-interface --domain ${SF3_PROXY_NAME} --type network \
        --source virbr4 \
        --mac ${SF3_PROXY_MAC2} --config --live

virsh attach-interface --domain ${SF3_PROXY_NAME} --type network \
        --source virbr5 \
        --mac ${SF3_PROXY_MAC3} --config --live


#************************************************
# Quick test to check VM content and connectivity
#************************************************

VM_IPs="${CLASSIFIER1_IP} \
   ${CLASSIFIER2_IP} \
   ${SFF1_IP} \
   ${SFF2_IP} \
   ${SF1_IP} \
   ${SF2_IP} \
   ${SF3_IP} \
   ${SF2_PROXY_IP} \
   ${SF3_PROXY_IP} \
   ${SF2_IP_ADMIN} \
   ${SF3_IP_ADMIN}"

for VM_IP in $VM_IPs;
do
 ssh-keygen -R $VM_IP
done

COMMAND="sudo ovs-vsctl show"

VM_IPs="${CLASSIFIER1_IP} \
   ${CLASSIFIER2_IP} \
   ${SFF1_IP} \
   ${SFF2_IP} \
   ${SF1_IP} \
   ${SF2_PROXY_IP} \
   ${SF3_PROXY_IP}"

for VM_IP in $VM_IPs;
do
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_IP ${COMMAND}
  if [ $? -ne 0 ]; then
    echo "Error testing. Aborting"
    exit -1
  fi
done

#************************************************
# Final preparation of VMs
#************************************************

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo /vagrant/ovs/setup_classifier_ovs.sh"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SFF1_IP} "sudo /vagrant/ovs/setup_sff_ovs.sh"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SF1_IP} "sudo nohup /vagrant/ovs/setup_sf.sh 2>&1 >sf1_log.log" &
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SFF2_IP} "sudo /vagrant/ovs/setup_sff_ovs.sh"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER2_IP} "sudo /vagrant/ovs/setup_classifier_ovs.sh" &
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SF2_PROXY_IP} "sudo nohup bash /vagrant/ovs/setup_sfc_proxy.sh 2>&1 >sf2proxy.log" &
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SF3_PROXY_IP} "sudo nohup bash /vagrant/ovs/setup_sfc_proxy.sh 2>&1 >sf3proxy.log" &

#************************************************
# Configure OpenDayLight server
#************************************************

./ovs/setup_odl.py

#************************************************
# Demo: Run ICMP and HTTP traffic
#************************************************
xterm -geometry 80x30+20+20 -bg darkblue -title "SF2PROXY Log" -e ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SF2_PROXY_IP} "tail -F proxy.log" &

xterm -geometry 80x30+600+20 -bg darkblue -title "SF3PROXY Log" -e ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${SF3_PROXY_IP} "tail -F proxy.log" &

xterm -geometry 80x30+20+450 -bg grey -fg black -title "User 1 shell" -e ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app bash" &

xterm -geometry 80x30+600+450 -bg grey -fg black -title "User 2 shell" -e ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app2 bash" &


sleep 20
#ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app ping -c 5 192.168.2.2"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app wget -t1 http://192.168.2.2/"

#ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app2 ping -c 5 192.168.2.2"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app2 wget -t1 http://192.168.2.2/"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app wget -t1 http://192.168.2.2/openvswitch-pki_2.6.1-1_all.deb"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app2 wget -t1 http://192.168.2.2/openvswitch-pki_2.6.1-1_all.deb"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app wget -t1 http://192.168.2.2/openvswitch-common_2.6.1-1_amd64.deb"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${CLASSIFIER1_IP} "sudo ip netns exec app2 wget -t1 http://192.168.2.2/openvswitch-common_2.6.1-1_amd64.deb"

exit 0
