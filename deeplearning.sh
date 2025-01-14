#!/usr/bin/env bash

## Linode/SSH Security Settings
#<UDF name="username" label="(Optional) The limited sudo user to be created for the Linode" default="">
#<UDF name="password" label="(Optional) The password for the limited sudo user" example="s3cure_p4ssw0rd" default="">
#<UDF name="pubkey" label="(Optional) The SSH Public Key that will be used to access the Linode" default="">
#<UDF name="disable_root" label="(Optional) Disable password authentication over SSH?" oneOf="Yes,No" default="No">

#<UDF name="os_access_key" label="(Optional) Access Key of Linode Object Storage" default="">
#<UDF name="os_secret_key" label="(Optional) Secret Key of Linode Object Storage" default="">
#<UDF name="os_region" label="(Optional) Region of Linode Object Storage" oneOf="nl-ams-1,us-southeast-1,in-maa-1,us-ord-1,eu-central-1,id-cgk-1,us-lax-1,es-mad-1,us-mia-1,it-mil-1,us-east-1,jp-osa-1,fr-par-1,br-gru-1,us-sea-1,ap-south-1,se-sto-1,us-iad-1" default="">
#<UDF name="os_bucketname" label="(Optional) Bucket Name of Linode Object Storage" default="">

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

# Mount Linode Object Storage
if [ -n "$OS_ACCESS_KEY" ] && [ -n "$OS_SECRET_KEY" ] && [ -n "$OS_REGION" ] && [ -n "$OS_BUCKETNAME" ]; then
    # Install Rclone
    curl https://rclone.org/install.sh | bash
    rclone version # This command is required to create the necessary directories

    # Configure Rclone to mount an external Linode Object Storage
    cat > /root/.config/rclone/rclone.conf <<EOF
[linode]
type = s3
provider = AWS
access_key_id = $OS_ACCESS_KEY
secret_access_key = $OS_SECRET_KEY
region = $OS_REGION
endpoint = $OS_REGION.linodeobjects.com
location_constraint = $OS_REGION
acl = private
EOF

    ln -s /usr/bin/rclone /sbin/mount.rclone
    mkdir -p /mnt/data

    cat > /etc/systemd/system/mnt-data.mount <<EOF
[Unit]
After=network-online.target

[Mount]
Type=rclone
What=linode:$OS_BUCKETNAME
Where=/mnt/data
Options=rw,allow_other,args2env,vfs-cache-mode=writes,config=/root/.config/rclone/rclone.conf,cache-dir=/var/rclone
EOF

    cat > /etc/systemd/system/mnt-data.automount <<EOF
[Unit]
DefaultDependencies=no
After=network-online.target
Before=remote-fs.target

[Automount]
Where=/mnt/data
TimeoutIdleSec=600

[Install]
WantedBy=multi-user.target
EOF

    systemctl start mnt-data.mount
    systemctl enable mnt-data.automount
fi

# Install CUDA drivers
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin
mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/12.6.2/local_installers/cuda-repo-ubuntu2404-12-6-local_12.6.2-560.35.03-1_amd64.deb
dpkg -i cuda-repo-ubuntu2404-12-6-local_12.6.2-560.35.03-1_amd64.deb
cp /var/cuda-repo-ubuntu2404-12-6-local/cuda-*-keyring.gpg /usr/share/keyrings/
apt-get update
apt-get -y install cuda-toolkit-12-6

# Install NVIDIA Driver
apt-get install -y nvidia-driver-560

# Install Docker
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Download Docker images
docker image pull nvcr.io/nvidia/pytorch:24.10-py3
docker image pull nvcr.io/nvidia/tensorflow:24.10-tf2-py3

# Create a shared directory on the host system
mkdir -p /root/shared

# Deploy a sample Jupyter notebook
cat > "/root/shared/Voice Recognition with OpenAI Whisper.ipynb" <<'EOF'
{ "cells": [ { "cell_type": "markdown", "id": "35e669b9", "metadata": {}, "source": [ "Maintainer: Hideki Okamoto @ Akamai Technologies" ] }, { "cell_type": "markdown", "id": "49ee943e", "metadata": {}, "source": [ "# Installing OpenAI Whisper" ] }, { "cell_type": "code", "execution_count": null, "id": "b5f495dd", "metadata": { "scrolled": true }, "outputs": [], "source": [ "# Installing FFmpeg\n", "# https://ffmpeg.org/\n", "%env DEBIAN_FRONTEND=noninteractive\n", "!apt update\n", "!apt -y install ffmpeg\n", "\n", "# Installing OpenAI Whisper\n", "# https://github.com/openai/whisper\n", "!pip install git+https://github.com/openai/whisper.git" ] }, { "cell_type": "markdown", "id": "fa235b46", "metadata": {}, "source": [ "# Downloading a sample speech\n", "If you want to try with another language, change \"en\" to the language code you prefer." ] }, { "cell_type": "code", "execution_count": null, "id": "b94bd983", "metadata": {}, "outputs": [], "source": [ "import IPython.display as ipd\n", "\n", "!wget -O audio.wav \"https://github.com/voxserv/audio_quality_testing_samples/raw/refs/heads/master/testaudio/48000/test01_20s.wav\"\n", "ipd.Audio(\"audio.wav\")" ] }, { "cell_type": "markdown", "id": "0e5ed68b", "metadata": {}, "source": [ "# Recognizing the speech with Whisper" ] }, { "cell_type": "code", "execution_count": null, "id": "ecf5dac2", "metadata": { "scrolled": true }, "outputs": [], "source": [ "!whisper --device cuda --model large audio.wav" ] } ], "metadata": { "kernelspec": { "display_name": "Python 3 (ipykernel)", "language": "python", "name": "python3" }, "language_info": { "codemirror_mode": { "name": "ipython", "version": 3 }, "file_extension": ".py", "mimetype": "text/x-python", "name": "python", "nbconvert_exporter": "python", "pygments_lexer": "ipython3", "version": "3.10.12" } }, "nbformat": 4, "nbformat_minor": 5 } 
EOF

# Define command aliases
if [ -n "$OS_ACCESS_KEY" ] && [ -n "$OS_SECRET_KEY" ] && [ -n "$OS_REGION" ] && [ -n "$OS_BUCKETNAME" ]; then
    cat > /root/.bash_profile <<'EOF'
alias pytorch="docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/shared/:/workspace/HOST-VOLUME/ -v /mnt/data/:/workspace/OBJECT-STORAGE/ --rm -it nvcr.io/nvidia/pytorch:24.10-py3"
alias tensorflow="docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/shared/:/workspace/HOST-VOLUME/ -v /mnt/data/:/workspace/OBJECT-STORAGE/ --rm -it nvcr.io/nvidia/tensorflow:24.10-tf2-py3"
alias pytorch-notebook="CID=\`docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/shared/:/workspace/HOST-VOLUME/ -v /mnt/data/:/workspace/OBJECT-STORAGE/ --rm -d nvcr.io/nvidia/pytorch:24.10-py3 jupyter notebook\`; sleep 5; docker logs \$CID 2>&1 | grep token"
alias tensorflow-notebook="CID=\`docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/shared/:/workspace/HOST-VOLUME/ -v /mnt/data/:/workspace/OBJECT-STORAGE/ --rm -d nvcr.io/nvidia/tensorflow:24.10-tf2-py3 jupyter notebook\`; sleep 5; docker logs \$CID 2>&1 | grep token"
alias stop-all-containers="docker kill \$(docker ps -q)"

if [[ `nvidia-smi` == *failed* ]]; then
	echo -e "\e[31mGPU is not available. This StackScript should be used for GPU instances.\e[m"
fi
EOF
else
    cat > /root/.bash_profile <<'EOF'
alias pytorch="docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/shared/:/workspace/HOST-VOLUME/ --rm -it nvcr.io/nvidia/pytorch:24.10-py3"
alias tensorflow="docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/shared/:/workspace/HOST-VOLUME/ --rm -it nvcr.io/nvidia/tensorflow:24.10-tf2-py3"
alias pytorch-notebook="CID=\`docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/shared/:/workspace/HOST-VOLUME/ --rm -d nvcr.io/nvidia/pytorch:24.10-py3 jupyter notebook\`; sleep 5; docker logs \$CID 2>&1 | grep token"
alias tensorflow-notebook="CID=\`docker run --gpus all --ipc=host --ulimit memlock=-1 --ulimit stack=67108864 -p 80:8888 -v /root/shared/:/workspace/HOST-VOLUME/ --rm -d nvcr.io/nvidia/tensorflow:24.10-tf2-py3 jupyter notebook\`; sleep 5; docker logs \$CID 2>&1 | grep token"
alias stop-all-containers="docker kill \$(docker ps -q)"

if [[ `nvidia-smi` == *failed* ]]; then
	echo -e "\e[31mGPU is not available. This StackScript should be used for GPU instances.\e[m"
fi
EOF
fi

# Configure Login Message
echo "Maintainer: Hideki Okamoto @ Akamai Technologies" > /etc/motd
echo "##############################################################################" >> /etc/motd
echo "You can launch a Docker container with each of the following commands:" >> /etc/motd
echo "" >> /etc/motd
echo -e "\e[33mpytorch\e[m: Log into an interactive shell of a container with Python and PyTorch." >> /etc/motd
echo -e "\e[33mtensorflow\e[m: Log into an interactive shell of a container with Python and TensorFlow." >> /etc/motd
echo -e "\e[33mpytorch-notebook\e[m: Start Jupyter Notebook with PyTorch as a daemon. You can access it at http://[Instance IP address]/" >> /etc/motd
echo -e "\e[33mtensorflow-notebook\e[m: Start Jupyter Notebook with TensorFlow as a daemon. You can access it at http://[Instance IP address]/" >> /etc/motd
echo "" >> /etc/motd
echo "Other commands:" >> /etc/motd
echo -e "\e[33mstop-all-containers\e[m: Stop all running containers." >> /etc/motd
echo "##############################################################################" >> /etc/motd

wall "StackScripts is finished. Please check /var/log/stackscript.log"
wall "Rebooting..."
reboot
