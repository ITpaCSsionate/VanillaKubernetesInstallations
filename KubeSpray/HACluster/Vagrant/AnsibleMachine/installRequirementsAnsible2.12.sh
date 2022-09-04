#!/bin/bash

echo $(pwd)

VENVDIR=kubespray-venv
KUBESPRAYDIR=/mnt/kubespray
ANSIBLE_VERSION=2.12
virtualenv  --python=$(which python3) $VENVDIR
source $VENVDIR/bin/activate
cd $KUBESPRAYDIR


python3 -m pip install -r requirements-2.12.txt

chmod 0400 /root/mastersKey

systemctl stop firewalld
systemctl disable firewalld


ansible-playbook -i inventory/mycluster/hosts.yml cluster.yml -b -v --private-key=/root/mastersKey



#test -f requirements-$ANSIBLE_VERSION.yml && \
#  ansible-galaxy role install -r requirements-$ANSIBLE_VERSION.yml && \
#  ansible-galaxy collection -r requirements-$ANSIBLE_VERSION.yml