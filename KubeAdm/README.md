# Introduction
## Purpose
The aim of this document is to provide a guide for installing Kubernetes in a Linux host **without having to worry about spending money in the cloud** (i.e, everything will be running in local). 

The idea is to have a cluster with 1 master nodes and 2 worker nodes (**so that we can test some applications there. If we wanted to test control plane HA, we would need to create a cluster with at  least 3 masters**). 
> **The specs I have used for this are CPU: Intel i5-10400, MEM: 16GB DDR4**


## Relevant Toolkit used
- Ubuntu 20.04 (host where the VMs are installed). The choice here does not matter much as long as it can run KVM. 
- Ubuntu server 22.04. It will be the OS installed in the nodes.
- KVM. We need to create VMs and, if possible, learn a new virtualization technology (goodbye virtualbox/vmware). 
- Kubeadm. This is what we actually want to install.


## Why doing it "the hard way"?
There are several ways of running a Kubernetes cluster locally. However, installing one from scratch is funnier as the official documentation **must** be followed. In addition, installing it is harder than using something like [minikube](https://minikube.sigs.k8s.io/docs/) or [rancher desktop](https://rancherdesktop.io), which is appealing to me.


## Alternatives
- [minikube](https://minikube.sigs.k8s.io/docs/)
- [rancher desktop](https://rancherdesktop.io)
- [microk8s](https://microk8s.io/)
- [k3s](https://k3s.io/)
- ...


# VMs creation
> **Modify anything needed in the commands, such as the names, sizes, paths, etc.**

1. Load the appropriate kernel modules:
```
sudo lsmod | grep kvm
sudo modprobe kvm_intel 
sudo modprobe kvm
```

2. Install the needed packages for KVM and configure them:
```
sudo apt update
sudo apt install -y qemu qemu-system libvirt-clients libvirt-daemon-system bridge-utils virt-manager
sudo systemctl enable libvirtd
sudo systemctl start libvirtd
sudo usermod -aG libvirt $(whoami)
```

3. Plan the Node IP range. In my case: 192.168.23.1/24 -> 192.168.23.1 netmask 255.255.0.0 (network 192.168.23.0/24) 

4. Create the Virtual Network. You can use [vnet.xml](./vnet.xml) and modify it if needed:
```
sudo virsh net-define vnet.xml
sudo virsh net-list --all
sudo virsh net-start k8s 
sudo virsh net-autostart k8s   
```

5. Create persistent storage for the VMs:
```
sudo mkdir -p /var/k8s_vms_storages/
sudo qemu-img create -f qcow2 -o preallocation=full /var/k8s_vms_storages/master0 20G
sudo qemu-img create -f qcow2 -o preallocation=full /var/k8s_vms_storages/worker0 20G
sudo qemu-img create -f qcow2 -o preallocation=full /var/k8s_vms_storages/worker1 20G
```

> We are allocating all the space with -o preallocation=full. It is not strictly required, however, it will help you prevent possible future storage issues


6. Install the VMs. The installation will require your interaction (such as choosing your language):
> You are advised to run each command in a differnt terminal so that you can install the 3 VMs at the same time
```
virt-install --name master0 --memory 4096 --vcpus 4 --cdrom ~/Downloads/ubuntu-22.04-live-server-amd64.iso --disk /var/k8s_vms_storages/master0 --os-type linux --os-variant ubuntu20.04 --network network=k8s --force --debug
virt-install --name worker0 --memory 2048 --vcpus 2 --cdrom ~/Downloads/ubuntu-22.04-live-server-amd64.iso --disk /var/k8s_vms_storages/worker0 --os-type linux --os-variant ubuntu20.04 --network network=k8s --force --debug
virt-install --name worker1 --memory 2048 --vcpus 2 --cdrom ~/Downloads/ubuntu-22.04-live-server-amd64.iso --disk /var/k8s_vms_storages/worker1 --os-type linux --os-variant ubuntu20.04 --network network=k8s --force --debug
```

**ATTENTION:** you need to remember the passwords of the hosts so that later on you can add a SSH key for accessing them.

7. Install OpenSSH on the VMs:
```
sudo apt install openssh-server openssl
sudo systemctl enable ssh
sudo systemctl daemon-reload
```

8. Get the MAC of the installed VMs:
```
virsh dumpxml master0 | grep mac
virsh dumpxml worker0 | grep mac
virsh dumpxml worker1 | grep mac
```

9. Configure DHCP for the network. Edit the file netBackup.xml and make the node IPs static
```
virsh net-edit --network k8s
```
Under the <dhcp> section, add:
```
<host mac='<masterMAC>' name='master0' ip='192.168.23.5'/>
<host mac='<worker0MAC>' name='worker0' ip='192.168.23.20'/>
<host mac='<worker1MAC>' name='worker1' ip='192.168.23.21'/>
```
Then, execute:
```
virsh net-destroy k8s
virsh net-start k8s
```
  
> Another option is to backup the network using virsh net-dumpxml --network k8s, edit the XML generated, remove the actual network and update it with the new configuration. Not tested.

10. Create a SSH key for the VMs:
```
ssh-keygen -t ed25519 -C "" -f VMsKey
```

11. Shutdown the VMs for the new DHCP options to be effective on the next boot.
> NOTE: when I tried it, I could not make dhclient work and I had to reboot the VMs.

12. In the VMs, install useful packages:
> Remember that now you can ssh to the VMs
```
sudo apt update
sudo apt -y upgrade
sudo apt install -y nmap telnet net-tools iotop
```

13. Copy the SSH key into the VMs:
```
ssh-keygen -R 192.168.23.5
ssh-keygen -R 192.168.23.20
ssh-keygen -R 192.168.23.21
ssh-copy-id -i VMsKey master0@192.168.23.5
ssh-copy-id -i VMsKey worker0@192.168.23.20
ssh-copy-id -i VMsKey worker1@192.168.23.21
```



# Cluster installation 
**These sections must be executed in the same order they are listed here**

## Cluster installation - All the VMs

1. Start the VMs:
```
virsh list --all
virsh start master0
virsh start worker0
virsh start worker1
```

2. Get the IPs (in case you have forgotten them):
```
virsh net-list
virsh net-dhcp-leases --network k8s
```

3. SSH into the VMs 
> An interesting utility for having all the ssh sessions in one terminal is [tmux](https://github.com/tmux/tmux), but it is not strictly required.

4. Configure the host accordingly, according to the [official kubernetes documentation](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
```
lsmod | grep br_netfilter
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

5. __(Not needed for Ubuntu Server 22.04): check the cgroups version of your os:__
```
grep cgroup /proc/filesystems
systemd --version | grep default-hierarchy=
```

> [Cgroups](https://man7.org/linux/man-pages/man7/cgroups.7.html) and [Namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html) are what allows container to exist. 


6. Install the container runtime. For this tutorial we are using [CRIO](https://github.com/cri-o/cri-o/blob/main/install.md#apt-based-operating-systems) (the author has experience with it as it is used in OpenShift 4.X):
```
sudo su


apt update
apt install -y curl gnupg libseccomp-dev
export OS=xUbuntu_20.04
echo $OS
export VERSION=1.23
echo $VERSION

echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list

mkdir -p /usr/share/keyrings
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

apt-get update
apt-get install -y cri-o cri-o-runc


export crictlVER="v1.23.0"
curl -L https://github.com/kubernetes-sigs/cri-tools/releases/download/$crictlVER/crictl-${crictlVER}-linux-amd64.tar.gz --output crictl-${crictlVER}-linux-amd64.tar.gz
sudo tar zxvf crictl-$crictlVER-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$crictlVER-linux-amd64.tar.gz


systemctl daemon-reload
systemctl enable crio
systemctl start crio
exit
```

7. Install kubeadm. [Official documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/):
```
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

## Cluster installation - Master node VM
1. Install the cluster
```
sudo su
kubeadm init --pod-network-cidr=10.23.0.0/16 --cri-socket unix:///var/run/crio/crio.sock --apiserver-advertise-address 192.168.23.5 2> installationErrs.log 1> installationLogs.log 
```

**Make sure you save the output of this command as it contains the command you will need to join other nodes to the cluster**

In case of errors:
```
sudo kubeadm reset 
sudo rm -rf /etc/cni/net.d 
sudo rm $HOME/.kube/config
sudo iptables --flush
```

2. Copy admin kubeconfig:
```
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

3. Add a CNI:
```
kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
wget https://projectcalico.docs.tigera.io/manifests/custom-resources.yaml -O calico-cr.yaml
```
Now, edit calico-cr and in the Installation object, in .spec.calicoNetwork.ipPools section, modify the CIDR to match the --pod-network-cidr specified in the kubeadm init (10.23.0.0/16). Then:

```
kubectl create -f calico-cr.yaml
sleep 30
sudo systemctl daemon-reload
sudo systemctl restart crio
```

> For debugging: journalctl -xeu crio.service

## Cluster installation - Worker VMs
1. SSH to the VM

2. Make sure you have swap disabled. If not, **the node will not be able to join the cluster**:
Edit /etc/fstab and remove any swap entries. Also, execute:
```
sudo swapoff --all
sudo mount --all
```

3. Join the node
```
sudo su
kubeadm join 192.168.23.5:6443 --token <tokenObtainedInTheMasterVM> --discovery-token-ca-cert-hash <hashObtainedInTheMasterVM> --v=7
```
	
In case of errors:
```
sudo kubeadm reset 
sudo rm -rf /etc/cni/net.d 
sudo rm -rf /etc/kubernetes
sudo rm -r $HOME/.kube
sudo iptables --flush
```

> For debugging: journalctl -xeu kubelet

4. Wait a few minutes until the CNI pods have been created in the new nodes.

> If you encounter issues when creating pods in the new nodes, such as this message: __Warning  FailedCreatePodSandBox  1s                   kubelet            Failed to create pod sandbox: rpc error: code = Unknown desc__ when describing pods, just execute: ``systemctl daemon-reload; systemctl restart crio``

## Cluster installation - Master node VM
1. Label the workers
```
kubectl label node worker1 node-role.kubernetes.io/worker=worker
kubectl label node worker0 node-role.kubernetes.io/worker=worker
```


# References
1. Cluster installation:
  - [Calico](https://projectcalico.docs.tigera.io)
  - [Kubernetes](https://kubernetes.io)
  - [CRIO](https://github.com/cri-o/cri-o/)
  
2. VMs installation: 
  - [Linuxconfig](https://linuxconfig.org/how-to-create-and-manage-kvm-virtual-machines-from-cli) 
  - [Computingforgeeks](https://computingforgeeks.com/how-to-create-and-configure-bridge-networking-for-kvm-in-linux/)
  - [Linuxconfig](https://linuxconfig.org/how-to-use-bridged-networking-with-libvirt-and-kvm)
  - [Debian wiki](https://wiki.debian.org/es/KVM)
  - [Libvirt](https://libvirt.org/storage.html)



# Improvements
- Simulate a bastion host
- Automations
