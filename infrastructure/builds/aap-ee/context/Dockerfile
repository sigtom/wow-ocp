# Modern Community-based EE build for OpenShift
FROM ghcr.io/ansible/community-ansible-dev-tools:latest

USER root

# 1. Install System Packages (RPMs) - Fedora uses dnf
RUN dnf -y install git sshpass openssh-clients bind-utils iputils && dnf clean all

# 2. Install Python Packages
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --upgrade pip && \
    pip3 install -r /tmp/requirements.txt

# 3. Install Ansible Collections
COPY requirements.yml /tmp/requirements.yml
RUN ansible-galaxy collection install -r /tmp/requirements.yml -p /usr/share/ansible/collections

# 4. Finalize
USER 1000
LABEL ansible-execution-environment=true
