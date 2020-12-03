K8S Bootstrap


# Base OS system

Choice is made on auto-updating Fedora CoreOS.

Last version shall be available from the official web site:
<https://getfedora.org/en/coreos/download>

## Produce ignition file

Fedora CoreOS need to use ignition to setup the system at first boot.

You can write a [FCCS](./ignition/node.fcc), then convert it into [ignition](./ignition/node.ign), using the converter.
Please cf. to [Producing an Ignition File](https://docs.fedoraproject.org/en-US/fedora-coreos/producing-ign/)

~~~~sh
podman pull quay.io/coreos/fcct:release
podman run -i --rm quay.io/coreos/fcct:release --pretty --strict <exampel.fcc> example.ign
~~~~

## coreos-install

If you choose to boot from a vanilla image disk, you shall have to install the system on disk using the coreos-install.

After autologin, use this kind of command line.

~~~~sh
sudo coreos-install /dev/sda --ignition-url https://pi.genesis.workoutperf.com/ignition/node.ign
~~~~

# Prepare system to install Kubernetes

After install and a reboot, you shall be able to connect through SSH.
Copy the [setup_system.sh](./setup_system.sh) file, and execute it on the fresh OS.

It will download requirements, make some system config and install kubeadm, kubelet and kubectl and the system.

# Install Kubernetes

If you want to setup a new cluster, you shall use the [cluster-config.yaml](./cluster-config.yaml)

RECOMMANDED, launch preflight checks
~~~~
sudo kubeadm init phase preflight --config cluster-config.yaml
~~~~

if no error, then launch for real

~~~~
sudo kubeadm init --config cluster-config.yaml
~~~~

# Untaint master nodes

~~~~
kubectl taint nodes --all node-role.kubernetes.io/master-
~~~~

# Install network

For now with use Calico.
Cf. [Calico Documentation](https://docs.projectcalico.org/getting-started/kubernetes/self-managed-onprem/onpremises)

The installation for less than 50 nodes shall be enougth
~~~~
 curl -fsSL https://docs.projectcalico.org/manifests/calico.yaml | sed -e "s/\/usr\/libexec/\/opt\/libexec/g" | kubectl create -f -
~~~~
REMARQS: as Fedora COREOS mount the /usr in readonly, the path shall be changed

Wait for calico node become ready.

# Install load-balancer

Install [metalLB](https://metallb.universe.tf/installation).

See what changes would be made, returns nonzero returncode if different
~~~~
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
sed -e "s/mode: \"\"/mode: \"ipvs\"/" | \
kubectl diff -f - -n kube-system
~~~~


Actually apply the changes, returns nonzero returncode on errors only
~~~~
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
sed -e "s/mode: \"\"/mode: \"ipvs\"/" | \
kubectl apply -f - -n kube-system
~~~~

Create a dedicated namespace, typicaly metallb-system and apply Kustomization of metalLB.
~~~~
kubectl create namespace metallb-system
kubectl create -n metallb-system -k network/metallb/deploy
~~~~

# Install Cert-Manager

Retrieve last version
~~~~
git clone --depth=1 --branch=v1.0.4 https://github.com/jetstack/cert-manager.git network/cert-manager/cert-manager
~~~~

WARNING: You shall need to update chart version and appVersion before install.
Edit with the expected version of branch extracted, in network/cert-manager/cert-manager/deploy/charts/cert-manager/Chart.yaml
~~~~yaml
apiVersion: v1
name: cert-manager
# The version and appVersion fields are set automatically by the release tool
version: v1.0.4
appVersion: v1.0.4
description: A Helm chart for cert-manager
home: https://github.com/jetstack/cert-manager
icon: https://raw.githubusercontent.com/jetstack/cert-manager/master/logo/logo.png
keywords:
  - cert-manager
  - kube-lego
  - letsencrypt
  - tls
sources:
  - https://github.com/jetstack/cert-manager
maintainers:
  - name: munnerz
    email: james@jetstack.io
~~~~

Edit the config in network/cert-manager/config.yaml
~~~~yaml
installCRDs: true

prometheus:
  enabled: false
~~~~



create the cert-manager namespace, and install with Helm.
~~~~
kubectl create namespace cert-manager
helm install -f network/cert-manager/config.yaml -n cert-manager cert-manager network/cert-manager/cert-manager/deploy/charts/cert-manager
~~~~

# Install Ingress (Treafik)

Retrieve last helm chart:
~~~~
git clone --depth=1 --branch=master https://github.com/traefik/traefik-helm-chart network/traefik/traefik-helm-chart
~~~~

Edit the config in network/traefik/config.yaml
~~~~yaml
ingressClass:
  enabled: true
  isDefaultClass: true

providers:
  kubernetesCRD:
    enabled: true

logs:
  general:
    level: INFO

ports:
  #web:
  #  redirectTo: websecure
  websecure:
    tls:
      enabled: true
      domains:
        - main: edge.fcos-k8s-single.genesis.workoutperf.com
          sans: 
            - traefik.edge.fcos-k8s-single.genesis.workoutperf.com
            - traefik.edge.fcos-k8s-single

service:
  spec:
    loadBalancerIP: "192.168.1.60"
~~~~

create the traefik namespace, and install with Helm.
~~~~
kubectl create namespace traefik-system
helm install -f network/traefik/config.yaml -n traefik-system traefik network/traefik/traefik-helm-chart/traefik
~~~~

