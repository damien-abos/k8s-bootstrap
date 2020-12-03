#!/usr/bin/env bash

CNI_VERSION=${CNI_VERSION:-"v0.8.7"}
CRICTL_VERSION=${CRICTL_VERSION:-"v1.19.0"}
DOWNLOAD_DIR=${DOWNLOAD_DIR:-/usr/local/bin}

sudo mkdir -p /opt/cni/bin
curl -fsSL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | sudo tar -C /opt/cni/bin -xz

sudo mkdir -p $DOWNLOAD_DIR
curl -fsSL "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-amd64.tar.gz" | sudo tar -C $DOWNLOAD_DIR -xz

RELEASE="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
cd $DOWNLOAD_DIR
sudo curl -fsSL --remote-name-all https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/amd64/{kubeadm,kubelet,kubectl}
sudo chmod +x {kubeadm,kubelet,kubectl}

RELEASE_VERSION="v0.4.0"

# requirement for network
cat << EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
net.ipv4.ip_forward=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
EOF

curl -fsSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service
sudo mkdir -p /etc/systemd/system/kubelet.service.d
curl -fsSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf" | sed "s:/usr/bin:${DOWNLOAD_DIR}:g" | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf

# Enforce kubelet to use systemd to detect cgroup
sudo mkdir -p /var/lib/kubelet
cat << EOF | sudo tee /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

# Disable SELinux (not a good option)
sudo setenforce 0
cat << EOF | sudo tee /etc/selinux/config
SELINUX=disabled
EOF

# requirements for k8s network
sudo rpm-ostree install --idempotent conntrack-tools ethtool

sudo systemctl daemon-reload
sudo systemctl enable docker.service
sudo systemctl enable kubelet.service
# requirement for longhorn storage
sudo systemctl enable iscsid.service

# Require to reboot to have rpm-opstree changes that take effect
sudo systemctl reboot
