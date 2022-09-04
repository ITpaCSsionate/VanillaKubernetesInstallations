# Differences between HA installation and non-HA installation

## Re-run kubespray inventory generator script (the previous one had 2 nodes that we are not creating now)
declare -a IPS=(192.168.230.3)
CONFIG_FILE=inventory/mycluster/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}


## Modify the deployments so that they tolerate control-plane taints
Not needed in daemonsets because they have the toleration:
``
      tolerations:
      - operator: Exists
``
[Source](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
After checking deployments, their taints have no operator (by default is Equal) and the taint is NoSchedule without value, so the only thing I had to do is to add the taint:
``kubectl taint nodes node1 node-role.kubernetes.io/control-plane="":NoSchedule``

## Add a taint to the control-plane node
kubectl taint nodes node1 node-role.kubernetes.io/control-plane="":NoSchedule


# Add worker

## Modify hosts.yml file(ansible VM)
``cd /mnt/kubespray/inventory/mycluster``

## Run the playbook(ansible VM)
Modify the hosts.yml file including the location of the private key for each host. 
The new content for the hosts.yml file is:
```
all:
  hosts:
    node1:
      ansible_host: 192.168.230.3
      ip: 192.168.230.3
      access_ip: 192.168.230.3
      ansible_ssh_private_key_file: /root/mastersKey
    node2:
      ansible_host: 192.168.228.10
      ip: 192.168.228.10
      access_ip: 192.168.228.10
      ansible_ssh_private_key_file: /root/workersKey
    node3:
      ansible_host: 192.168.228.11
      ip: 192.168.228.11
      access_ip: 192.168.228.11
      ansible_ssh_private_key_file: /root/workersKey
  children:
    kube_control_plane:
      hosts:
        node1:
    kube_node:
      hosts:
        node1:
        node2: 
        node3:
    etcd:
      hosts:
        node1:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
```

Vagrant halt+ vagrant up the ansible VM (to resync the folder) and:
```
VENVDIR=kubespray-venv
KUBESPRAYDIR=/mnt/kubespray
ANSIBLE_VERSION=2.12
virtualenv  --python=$(which python3) $VENVDIR
source $VENVDIR/bin/activate
cd $KUBESPRAYDIR

python3 -m pip install -r requirements-2.12.txt



chmod 0400 /root/mastersKey
chmod 0400 /root/workersKey
ansible-playbook -i inventory/mycluster/hosts.yml scale.yml -b -vvv
```

During the execution of the playbook, I had to modify /etc/systemd/resolved.conf and systemctl restart systemd-resolved.service when it got stucked on node1 as it could not access the Internet. 

## Restart the master node
> Because of DNS issues...  should not be happening and it is not happening on the newly added workers...

## Add labels to the nodes
kubectl label node node2 node-role.kubernetes.io/worker=""
kubectl label node node3 node-role.kubernetes.io/worker=""
kubectl label node node2 node-az="az1"
kubectl label node node3 node-az="az2"

## Solve DNS issues in the worker nodes
modify /etc/systemd/resolved.conf adding in the DNS= line the value 8.8.8.8
reboot the nodes