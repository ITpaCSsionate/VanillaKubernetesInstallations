#!/usr/bin/python
import os

with open("/etc/fstab", "r+") as file:
    lines = file.readlines()
with open("/tmp/.fstabtemp", "w") as filetwo:
    for line in lines: 
        if "swap" not in line:
            filetwo.write(line)
try:
    os.replace("/tmp/.fstabtemp", "/etc/fstab")
except exception as e:
    print(e)

    