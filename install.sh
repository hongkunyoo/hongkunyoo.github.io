# https://github.com/conda-forge/miniforge
# golang

########################################
# Debian
########################################
export DEBIAN_FRONTEND=noninteractive

apt update
apt install -y software-properties-common 
apt install -y gcc build-essential vim dnsutils docker.io file wget curl tmux tcpdump ca-certificates git libcurl4-openssl-dev libssl-dev procps



########################################
# CentOS
########################################
