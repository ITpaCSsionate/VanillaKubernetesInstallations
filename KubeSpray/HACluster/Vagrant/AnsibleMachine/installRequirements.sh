#!/bin/bash


## refresh yum cache
returnValue=$(dnf makecache --refresh)
## yum update
returnValue=$(yum -y update)
## ensure python3 and python3-pip
returnValue=$(yum install -y python3 python3-pip python3-jinja2)


python3 -m pip install virtualenv
echo "installing venv" > /tmp/installed.txt
echo $(which virtualenv) >> /tmp/installed.txt