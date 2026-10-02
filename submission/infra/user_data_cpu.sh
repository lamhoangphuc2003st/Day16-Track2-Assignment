#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t startup-script -s 2>/dev/console) 2>&1

echo "Starting startup script for CPU LightGBM benchmark node"

apt-get update -y
apt-get install -y python3 python3-pip

# Debian 12 marks the system Python as externally managed (PEP 668);
# --break-system-packages is required for a system-wide pip install here.
pip3 install --break-system-packages --upgrade pip
pip3 install --break-system-packages lightgbm scikit-learn pandas numpy kaggle

echo "CPU environment ready: lightgbm, scikit-learn, pandas, numpy, kaggle installed system-wide."
