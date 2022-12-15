#!/usr/bin/env bash

## Linode/SSH Security Settings
#<UDF name="username" label="The limited sudo user to be created for the Linode" default="">
#<UDF name="password" label="The password for the limited sudo user" example="s3cure_p4ssw0rd" default="">
#<UDF name="pubkey" label="The SSH Public Key that will be used to access the Linode" default="">
#<UDF name="disable_root" label="Disable password authentication over SSH?" oneOf="Yes,No" default="No">

## Enable logging
set -o pipefail
exec > >(tee /dev/ttyS0 /var/log/stackscript.log) 2>&1

## Import the Bash StackScript Library
source <ssinclude StackScriptID=1>

## Import the OCA Helper Functions
source <ssinclude StackScriptID=401712>

## Run initial configuration tasks (DNS/SSH stuff, etc...)
source <ssinclude StackScriptID=666912>

## Update system & set hostname & basic security
set_hostname
apt_setup_update
ufw_install
ufw allow 80/tcp

## Time sync configuration
sed -i "s/^#NTP=/NTP=pool.ntp.org/" /etc/systemd/timesyncd.conf
systemctl restart systemd-timesyncd

# Install CUDA drivers
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-ubuntu2204.pin
mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/12.0.0/local_installers/cuda-repo-ubuntu2204-12-0-local_12.0.0-525.60.13-1_amd64.deb
dpkg -i cuda-repo-ubuntu2204-12-0-local_12.0.0-525.60.13-1_amd64.deb
cp /var/cuda-repo-ubuntu2204-12-0-local/cuda-*-keyring.gpg /usr/share/keyrings/
apt update
apt -y install cuda-drivers

# Install Docker
curl https://get.docker.com | sh
systemctl enable docker
systemctl start docker

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey -o /etc/apt/trusted.gpg.d/nvidia-docker-key.gpg
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
apt update
apt install -y nvidia-docker2
systemctl restart docker

# Download Docker images
docker image pull nvcr.io/nvidia/pytorch:22.11-py3
docker image pull nvcr.io/nvidia/tensorflow:22.11-tf2-py3

# Define command aliases
cat > /root/.bash_profile <<'EOF'
alias pytorch="docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/:/workspace/host-volume/ --rm -it nvcr.io/nvidia/pytorch:22.11-py3"
alias tensorflow="docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/:/workspace/host-volume/ --rm -it nvcr.io/nvidia/tensorflow:22.11-tf2-py3"
alias pytorch-notebook="CID=\`docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/:/workspace/host-volume/ --rm -d nvcr.io/nvidia/pytorch:22.11-py3 jupyter notebook\`; sleep 5; docker logs \$CID 2>&1 | grep token"
alias tensorflow-notebook="CID=\`docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/:/workspace/host-volume/ --rm -d nvcr.io/nvidia/tensorflow:22.11-tf2-py3 jupyter notebook\`; sleep 5; docker logs \$CID 2>&1 | grep token"
alias stop-all-containers="docker kill \$(docker ps -q)"
EOF

# Configure Login Message
echo "##############################################################################" > /etc/motd
echo "You can launch a Docker container with each of the following commands:" >> /etc/motd
echo "" >> /etc/motd
echo -e "\e[33mpytorch\e[m: Log into an interactive shell of a container with Python and PyTorch." >> /etc/motd
echo -e "\e[33mtensorflow\e[m: Log into an interactive shell of a container with Python and TensorFlow." >> /etc/motd
echo -e "\e[33mpytorch-notebook\e[m: Start Jupyter Notebook with PyTorch as a daemon. You can access it at http://[Instance IP address]/" >> /etc/motd
echo -e "\e[33mtensorflow-notebookm\e[m: Start Jupyter Notebook with TensorFlow as a daemon. You can access it at http://[Instance IP address]/" >> /etc/motd
echo "" >> /etc/motd
echo "Other commands:" >> /etc/motd
echo -e "\e[33mstop-all-containers\e[m: Stop all running containers." >> /etc/motd
echo "##############################################################################" >> /etc/motd

wall "StackScripts is finished. Please check /var/log/stackscript.log"
