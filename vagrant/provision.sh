#!/usr/bin/env bash
set -euxo pipefail

dnf -y upgrade --refresh

# The vagrant-disksize plugin grows the virtual disk and partition, but not the
# filesystem inside it - without this the box runs on the image's original 5GB.
dnf -y install cloud-utils-growpart
growpart /dev/sda 3 || true
btrfs filesystem resize max /
dnf -y install git maven dnf-plugins-core unzip jq helm awscli2

# JDK 17 - Fedora 44 dropped java-17-openjdk, and maven pulls in JDK 25 as a
# dependency, so Temurin 17 needs explicit alternatives priority to match the
# wildfly:31.0.1.Final-jdk17 runtime the app actually deploys onto.
cat >/etc/yum.repos.d/adoptium.repo <<'REPOEOF'
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/fedora/$releasever/$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
REPOEOF
dnf -y install temurin-17-jdk
# Fedora derives alternatives priority from the version string (java-25-openjdk
# registers at 25000421), so no sane priority outranks it. Pin with --set instead.
alternatives --install /usr/bin/java java /usr/lib/jvm/java-17-temurin-jdk/bin/java 3000 --follower /usr/bin/keytool keytool /usr/lib/jvm/java-17-temurin-jdk/bin/keytool
alternatives --install /usr/bin/javac javac /usr/lib/jvm/java-17-temurin-jdk/bin/javac 3000
alternatives --set java /usr/lib/jvm/java-17-temurin-jdk/bin/java
alternatives --set javac /usr/lib/jvm/java-17-temurin-jdk/bin/javac
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-temurin-jdk' > /etc/profile.d/java17.sh

dnf -y config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo \
  || dnf -y config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker vagrant

dnf -y config-manager addrepo --from-repofile=https://rpm.releases.hashicorp.com/fedora/hashicorp.repo \
  || dnf -y config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
dnf -y install terraform

K8S_MINOR="v1.31"
cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/rpm/repodata/repomd.xml.key
EOF
dnf -y install kubectl

java -version
mvn -version
docker --version
docker compose version
terraform version
kubectl version --client
helm version
aws --version
# Shell environment: zsh + Oh My Zsh + Powerlevel10k, plus CLI tools.
# Provisioning runs as root, so the user-level parts run via sudo -u vagrant.
dnf -y install zsh util-linux-user bind-utils fzf ripgrep bat tree
sudo -u vagrant sh -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
sudo -u vagrant git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /home/vagrant/.oh-my-zsh/custom/themes/powerlevel10k
sudo -u vagrant git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions /home/vagrant/.oh-my-zsh/custom/plugins/zsh-autosuggestions
sudo -u vagrant git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting /home/vagrant/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
sudo -u vagrant sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' /home/vagrant/.zshrc
sudo -u vagrant sed -i 's|^plugins=.*|plugins=(git docker docker-compose kubectl helm terraform aws fzf zsh-autosuggestions zsh-syntax-highlighting)|' /home/vagrant/.zshrc
chsh -s /bin/zsh vagrant
install -o vagrant -g vagrant -m 644 /vagrant/p10k.zsh /home/vagrant/.p10k.zsh 2>/dev/null || true
