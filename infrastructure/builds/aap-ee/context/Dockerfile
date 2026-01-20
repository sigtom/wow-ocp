# Simple robust EE build for OpenShift
FROM registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel9:latest

USER root

# 1. Install System Packages (RPMs)
COPY bindep.txt /tmp/bindep.txt
RUN microdnf -y install git sshpass openssh-clients bind-utils iputils && microdnf clean all

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
