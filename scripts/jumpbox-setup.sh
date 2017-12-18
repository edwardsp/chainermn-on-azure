#!/bin/bash

#############################################################################
log()
{
	echo "$1"
}

while getopts :a:k:u:t:p optname; do
	log "Option $optname set with value ${OPTARG}"
	case $optname in
		a)  # storage account
			export AZURE_STORAGE_ACCOUNT=${OPTARG}
			;;
		k)  # storage key
			export AZURE_STORAGE_ACCESS_KEY=${OPTARG}
			;;
	esac
done

# Shares
SHARE_HOME=/share/home
SHARE_SCRATCH=/share/scratch
SHARE_APPS=/share/apps

# User
HPC_USER=hpcuser
HPC_UID=7007
HPC_GROUP=hpc
HPC_GID=7007

setup_disks()
{
    mkdir -p $SHARE_HOME
    mkdir -p $SHARE_SCRATCH
    mkdir -p $SHARE_APPS
}
is_ubuntu()
{
	python -mplatform | grep -qi Ubuntu
	return $?
}
is_centos()
{
	python -mplatform | grep -qi CentOS
	return $?
}
setup_user()
{
    # disable selinux
    if is_centos; then    
		sed -i 's/enforcing/disabled/g' /etc/selinux/config
		setenforce permissive
    fi
    groupadd -g $HPC_GID $HPC_GROUP

    # Don't require password for HPC user sudo
    echo "$HPC_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    
    # Disable tty requirement for sudo
    sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers
   
	useradd -c "HPC User" -g $HPC_GROUP -m -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER

	mkdir -p $SHARE_HOME/$HPC_USER/.ssh
	
	# Configure public key auth for the HPC user
	ssh-keygen -t rsa -f $SHARE_HOME/$HPC_USER/.ssh/id_rsa -q -P ""
	cat $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub >> $SHARE_HOME/$HPC_USER/.ssh/authorized_keys

	echo "Host *" > $SHARE_HOME/$HPC_USER/.ssh/config
	echo "    StrictHostKeyChecking no" >> $SHARE_HOME/$HPC_USER/.ssh/config
	echo "    UserKnownHostsFile /dev/null" >> $SHARE_HOME/$HPC_USER/.ssh/config
	echo "    PasswordAuthentication no" >> $SHARE_HOME/$HPC_USER/.ssh/config

	# Fix .ssh folder ownership
	chown -R $HPC_USER:$HPC_GROUP $SHARE_HOME/$HPC_USER

	# Fix permissions
	chmod 700 $SHARE_HOME/$HPC_USER/.ssh
	chmod 644 $SHARE_HOME/$HPC_USER/.ssh/config
	chmod 644 $SHARE_HOME/$HPC_USER/.ssh/authorized_keys
	chmod 600 $SHARE_HOME/$HPC_USER/.ssh/id_rsa
	chmod 644 $SHARE_HOME/$HPC_USER/.ssh/id_rsa.pub
	
	chown $HPC_USER:$HPC_GROUP $SHARE_SCRATCH
}
install_intelmpi()
{
  cd /opt
  sudo mv intel intel_old
  sudo curl -L -O http://registrationcenter-download.intel.com/akdlm/irc_nas/tec/11595/l_mpi_2017.3.196.tgz
  sudo tar zxvf l_mpi_2017.3.196.tgz
  sudo rm -rf l_mpi_2017.3.196.tgz
  cd l_mpi_2017.3.196
  sudo sed -i -e "s/decline/accept/g" silent.cfg
  sudo ./install.sh --silent silent.cfg
}
mount_nfs()
{
	if is_centos; then
		log "install NFS CentOS"
		yum -y install nfs-utils nfs-utils-lib
		echo "$SHARE_HOME    *(rw,async)" >> /etc/exports
		echo "/mnt/resource  *(rw,async)" >> /etc/exports
		systemctl enable rpcbind || echo "Already enabled"
		systemctl enable nfs-server || echo "Already enabled"
		systemctl start rpcbind || echo "Already enabled"
		systemctl start nfs-server || echo "Already enabled"
	fi
	if is_ubuntu; then
		log "Install NFS on Ubuntu"	
		sudo apt-get update
		sudo apt-get -y install nfs-kernel-server
		echo "$SHARE_HOME    *(rw,async)" >> /etc/exports
		echo "/mnt/resource  *(rw,async)" >> /etc/exports
		exportfs -a
		sudo systemctl enable nfs-kernel-server.service
		sudo systemctl start nfs-kernel-server.service
	fi	
}
SETUP_MARKER=/var/tmp/master-setup.marker
if [ -e "$SETUP_MARKER" ]; then
    echo "We're already configured, exiting..."
    exit 0
fi
install_intelmpi
setup_disks
mount_nfs
setup_user
# Create marker file so we know we're configured
touch $SETUP_MARKER
exit 0
