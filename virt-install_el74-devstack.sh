#!/bin/bash -x

NAME=$(echo $(basename $0)|sed -e 's/^.*virt-install_//g' -e 's/\.sh$//g')
HNAM=$(echo $NAME|sed -e 's/\(.*\)/\L\1/' -e 's/\./\-/g')
if [ $NAME != $HNAM ];then echo;read -p "libvirt Domain name: \"$NAME\" is DIFFERNT from Hostname: \"$HNAM\", REALLY continue ?? ";echo;fi
set -x
VARIANT=rhel7.4 # refer this value by '# osinfo-query os | grep rhel7'
POL=/var/lib/libvirt/images
ISO=${POL}/rhel-server-7.4-x86_64-dvd.iso

CPU=4
MEM=28672 #MB
MMX=28672 #MB
HDD=100   #GB
NIC=virbr1
NIC=br0
MAC=52:54:00:3e:6b:25

cat > /tmp/${NAME}-ks.cfg << EOF
cdrom
firstboot --disable
ignoredisk --only-use=sda
# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
# System language
lang en_US.UTF-8

# Network information
network  --bootproto=dhcp --device=eth0 --ipv6=auto --hostname=${HNAM}.example.com 
# Root password
rootpw redhat
# System timezone
timezone Asia/Tokyo
# System bootloader configuration
bootloader --location=mbr --boot-drive=sda
#autopart --type=lvm
# Partition clearing information
clearpart --all --initlabel --drives=sda
# Disk partitioning information
part /boot --fstype="xfs"  --ondisk=sda --size=500
part /     --fstype="xfs"  --ondisk=sda --size=500 --grow
part swap  --fstype="swap" --ondisk=sda --size=4096

%packages
%end

reboot

%post

cat > /etc/yum.repos.d/RHEL7DVD.repo << EOR
[DVD]
name=DVD
baseurl=file:///media
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
skip_broken=1
skip_if_unavailable=1
EOR

cat >> /root/.bashrc << EOB
export TERM=xterm
export FLOATING_RANGE=172.16.0.224/27
resize
EOB

#raw
cat >> /root/install_devstack << 'EOE'
#!/bin/bash -x

USERNAME=
PASSWORD=
POOLID=

subscription-manager unsubscribe --all
subscription-manager unregister
subscription-manager register --username=\$USERNAME --password=\$PASSWORD --force
subscription-manager attach --pool=\$POOLID
subscription-manager identity

subscription-manager repos --disable "*"
subscription-manager repos --enable rhel-7-server-rpms --enable rhel-7-server-optional-rpms

mount /dev/sr0 /media
yum -y upgrade
yum -y install git vim xterm redhat-lsb-core
rpm -ivh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
adduser stack
echo stack | passwd stack --stdin
usermod -G wheel stack -a
sed -i -e 's/^%wheel/#%wheel/g' -e 's/^# %wheel/%wheel/g' /etc/sudoers
cat >> /home/stack/.bashrc << EOC
export TERM=xterm
export FLOATING_RANGE=172.16.0.224/27
resize
EOC

sudo su - stack -c 'git clone https://github.com/openstack-dev/devstack.git'
sudo su - stack -c 'cd /home/stack/devstack;git checkout stable/pike'
echo '' | sudo tee /etc/sysconfig/iptables
sudo systemctl restart iptables
sudo su - stack -c 'cat << EOL > /home/stack/devstack/local.conf
ADMIN_PASSWORD=pass
DATABASE_PASSWORD=pass
RABBIT_PASSWORD=pass
SERVICE_PASSWORD=pass
EOL'
sudo su - stack -c 'cd /home/stack/devstack;./stack.sh'

EOE
#end raw

chmod 755 /root/install_devstack

mkdir /root/.ssh
chmod 700 /root/.ssh
chcon -t ssh_home_t /root/.ssh

cat > /root/.ssh/authorized_keys << EOS
ssh-rsa ...
EOS

chmod 600 /root/.ssh/authorized_keys
chcon -t ssh_home_t /root/.ssh/authorized_keys 

%end

EOF


sudo setenforce 0
sudo mkdir -pv ${POL}/${NAME}_iso
sudo umount -v ${POL}/${NAME}_iso
sudo mount -vo loop ${ISO} ${POL}/${NAME}_iso

virsh dominfo ${NAME} && \
	{ virsh destroy ${NAME}; rm -fv $(virsh dumpxml ${NAME}|awk -F\' '/source file.*(qcow2|img)/ { print $2; }'); virsh detach-disk ${NAME} --target sda --persistent && virsh undefine ${NAME}; }

virt-install \
    --connect=qemu:///system \
    --name=${NAME} \
    --memory=${MEM},maxmemory=${MMX} \
    --vcpus=${CPU} \
    --autostart \
    --nographics \
    --virt-type kvm \
    --machine pc \
    --cpu=host \
    --os-variant=${VARIANT} \
    --controller type=scsi,model=virtio-scsi \
    --disk path=${POL}/${NAME}.qcow2,size=${HDD},bus=scsi,cache=unsafe \
    --disk path=${ISO},device=cdrom \
    --force \
    --network bridge=${NIC},model=virtio,mac=${MAC} \
    --location=${POL}/${NAME}_iso \
    --console pty,target_type=serial \
    --extra-args="text biosdevname=0 net.ifnames=0 lang= console=tty0 console=ttyS0,115200 serial rd_NO_PLYMOUTH ks=file:/${NAME}-ks.cfg" \
    --initrd-inject=/tmp/${NAME}-ks.cfg


