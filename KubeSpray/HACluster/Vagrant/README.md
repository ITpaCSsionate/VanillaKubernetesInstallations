# Start by installing vagrant libvirt requirements
```
sudo apt install qemu libvirt-daemon-system libvirt-clients libxslt-dev libxml2-dev libvirt-dev zlib1g-dev ruby-dev ruby-libvirt ebtables dnsmasq-base
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -

sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"

sudo apt-get update && sudo apt-get install vagrant

sudo apt-get install qemu-utils libvirt-dev ruby-dev

vagrant plugin install vagrant-libvirt
```
> Not needed: vagrant plugin install vagrant-mutate

> vagrant init ubuntu/focal64
> Ideally we would use libvirt as a provider, but ubuntu/focal64 does not support it. 

Run the vms (vagrant up)




# Get kubespray and edit [Source1](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md), [Source2](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md#building-your-own-inventory)
```
git clone https://github.com/kubernetes-sigs/kubespray

python3 -m pip install ruamel.yaml
python3 contrib/inventory_builder/inventory.py help


## workers -> 192.168.228.10 192.168.228.11 
## masters -> 192.168.230.3 192.168.230.4 192.168.230.5

cp -r inventory/sample inventory/mycluster
declare -a IPS=(192.168.230.3 192.168.230.4 192.168.230.5)
CONFIG_FILE=inventory/mycluster/hosts.yml python3 contrib/inventory_builder/inventory.py ${IPS[@]}


cat inventory/mycluster/hosts.yml
```


# Create the cluster
**Ansible VM**
```
vagrant up
ssh-keygen -R 192.168.50.5
ssh -i ansiblevmKey root@192.168.50.5
cd /mnt/kubespray

ansible-playbook -i inventory/mycluster/hosts.yml cluster.yml -b -v --private-key=/root/mastersKey
```

[Reference](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/ansible.md)





## found 1st issue. ETCD could not start (etcd peers could not speak to others)
was caused because fedora comes with pre-configured firewall-cmd rules. I disabled firewall-cmd in the Vagrantfile.
-> disable firewall cmd

> Solved

## found 2nd issue. 
```
[root@node1 ~]# kubectl logs -f nodelocaldns-9nc5j -n kube-system
2022/08/22 18:16:12 [INFO] Starting node-cache image: 1.21.1
2022/08/22 18:16:12 [INFO] Using Corefile /etc/coredns/Corefile
2022/08/22 18:16:12 [INFO] Using Pidfile 
2022/08/22 18:16:15 [ERROR] Failed to read node-cache coreFile /etc/coredns/Corefile.base - open /etc/coredns/Corefile.base: no such file or directory
2022/08/22 18:16:15 [INFO] Skipping kube-dns configmap sync as no directory was specified
cluster.local.:53 on 169.254.25.10
in-addr.arpa.:53 on 169.254.25.10
ip6.arpa.:53 on 169.254.25.10
.:53 on 169.254.25.10
[INFO] plugin/reload: Running configuration MD5 = adf97d6b4504ff12113ebb35f0c6413e
CoreDNS-1.7.0
linux/amd64, go1.16.8, 
[FATAL] plugin/loop: Loop (169.254.25.10:55583 -> 169.254.25.10:53) detected for zone ".", see https://coredns.io/plugins/loop#troubleshooting. Query: "HINFO 5685135666098706724.5086278856509779791."
```
If we have a look at /etc/resolv.conf, we see the line:
``# This file is managed by man:systemd-resolved(8). Do not edit.``
Which means the issue was perfectly documented in the provided link. 

169.254.25.10 was the nameserver in /run/XX/resolv.conf and 127.0.0.53 in /etc/resolv.conf

the first IP is APIPA protocol, which means the solution is not the one provided in the link. Therefore, vim /etc/systemd/resolved.conf:
and add in the DNS= entry, the google dns server (8.8.8.8)
systemctl restart systemd-resolved

then remove nodelocaldns pods from kube-system namespace. Try it more than one time as it takes a while until they stop crashlooping.

> Solved

# Issues that could not be solved
Running  3 masters with the resources I had assigned to them was not possible in my computer (etcd was slow). I was using a partition on a non-SSD disk and I had assigned few resources to the masters... 

Therefore, I could not run a cluster with 3 master nodes. So I switched to 1 master node and more workers.