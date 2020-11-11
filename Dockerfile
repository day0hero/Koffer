FROM centos:latest as rpm
FROM registry:2 as registry
FROM docker.io/cloudctl/koffer-go:latest as koffer-go
FROM quay.io/openshift/origin-operator-registry:latest as olm
FROM registry.access.redhat.com/ubi8/ubi:latest as ubi8
FROM registry.access.redhat.com/ubi8/ubi:latest as ubi
FROM registry.access.redhat.com/ubi8/ubi:latest
#################################################################################
# OCP Version set in src/ocp
ARG varVerOpenshift="${varVerOpenshift}"
ARG varVerTerraform="${varVerTerraform}"
ARG varVerHelm="${varVerHelm}"
ARG varVerJq="${varVerJq}"

# OC Download Urls
ARG varUrlGit="${varUrlGit}"
ARG urlOC="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${varVerOpenshift}/openshift-client-linux.tar.gz"
ARG urlOCINST="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${varVerOpenshift}/openshift-install-linux.tar.gz"

# Binary Artifact URLS
ARG varUrlGcloud="https://sdk.cloud.google.com"
ARG varUrlHelm="https://get.helm.sh/helm-v${varVerHelm}-linux-amd64.tar.gz"
ARG urlRelease="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/release.txt"
ARG varUrlTerraform="https://releases.hashicorp.com/terraform/${varVerTerraform}/terraform_${varVerTerraform}_linux_amd64.zip"
ARG varUrlOsInst="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${varVerOpenshift}/openshift-install-linux.tar.gz"
ARG varUrlOpenshift="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${varVerOpenshift}/openshift-client-linux.tar.gz"
ARG varUrlJq="https://github.com/stedolan/jq/releases/download/jq-${varVerJq}/jq-linux64"

# Build Variables
ARG listManifest="/var/lib/koffer/release.list"

#################################################################################
# Package Lists
ARG varListRpms="\
             git \
             tree \
             tmux \
             pigz \
             rsync \
             unzip \
             skopeo \
             bsdtar \
             podman \
             buildah \
             openssl \
             httpd-tools \
             python3-pip \
             openssh-clients \
             fuse-overlayfs \
             "
ARG varListPip="\
             ansible \
             passlib \
             "
ARG YUM_FLAGS="\
    -y \
    --nobest \
    --allowerasing \
    --setopt=tsflags=nodocs \
    --disablerepo "ubi-8-appstream" \
    --disablerepo="ubi-8-codeready-builder" \
    --disablerepo="ubi-8-baseos" \
"
#################################################################################
# Load Artifacts

# From Repo
COPY bin/entrypoint /usr/bin/entrypoint
COPY bin/run_registry.sh /usr/bin/run_registry.sh
COPY conf/registry-config.yml /etc/docker/registry/config.yml
COPY conf/registries.conf /etc/containers/registries.conf

# From entrypoint cradle
COPY --from=koffer-go /root/koffer /usr/bin/koffer

# From origin-operator-registry:latest
COPY --from=olm /bin/registry-server  /usr/bin/registry-server
COPY --from=olm /bin/initializer  /usr/bin/initializer

# From Registry:2
COPY --from=registry /bin/registry  /bin/registry

# From CentOS
COPY --from=rpm /etc/pki/ /etc/pki
COPY --from=rpm /etc/yum.repos.d/ /etc/yum.repos.d

# From CentOS (aux testing)
COPY --from=rpm /etc/os-release /etc/os-release
COPY --from=rpm /etc/redhat-release /etc/redhat-release
COPY --from=rpm /etc/system-release /etc/system-release
#################################################################################
# Create Artifact Directories
RUN set -ex                                                                     \
     && mkdir -p /var/lib/koffer/                                               \
     && curl -sL ${urlRelease}                                                  \
      | awk -F'[ ]' '/Pull From:/{print $3}'                                    \
      | sed 's/quay.io\///g'                                                    \
      | tee -a ${listManifest}                                                  \
     && curl -sL ${urlRelease}                                                  \
      | grep -v 'Pull From'                                                     \
      | awk '/quay.io\/openshift-release/{print $2}'                            \
      | sed 's/quay.io\///g'                                                    \
      | tee -a ${listManifest}                                                  \
     && dnf update ${YUM_FLAGS}                                                 \
     && dnf -y module disable container-tools \
     && dnf -y install 'dnf-command(copr)' \
     && dnf -y copr enable rhcontainerbot/container-selinux \
     && curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo \
          https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/CentOS_8/devel:kubic:libcontainers:stable.repo \
     && dnf update ${YUM_FLAGS}                                                 \
     && dnf install ${YUM_FLAGS} ${varListRpms}                                 \
     && pip3 install ${varListPip}                                              \
     && dnf install ${YUM_FLAGS} bsdtar tar                                     \
     && terraform version                                                       \
     && curl -L ${varUrlHelm}                                                   \
          | tar xzvf - --directory /tmp linux-amd64/helm                        \
     && mv /tmp/linux-amd64/helm   /bin/                                        \
     && curl -L ${varUrlTerraform}                                              \
          | bsdtar -xvf- -C /bin                                                \
     && curl -L ${varUrlJq}                                                     \
             -o /bin/jq                                                         \
     && chmod +x /bin/{helm,terraform,jq}                                       \
     && chmod +x /usr/bin/entrypoint                                            \
     && mkdir /root/.bak && mv                                                  \
          /root/original-ks.cfg                                                 \
          /root/anaconda-ks.cfg                                                 \
          /root/anaconda-post-nochroot.log                                      \
          /root/anaconda-post.log                                               \
          /root/buildinfo                                                       \
        /root/.bak/                                                             \
    && rm -rf                                                                   \
        /var/cache/*                                                            \
        /var/log/dnf*                                                           \
        /var/log/yum*                                                           \
     && mkdir -p /root/deploy/{mirror,images}                                   \
     && mkdir -p /root/bundle                                                   \
     && mkdir -p /manifests                                                     \
     && mkdir -p /db                                                            \
     && touch /db/bundles.db                                                    \
     && initializer                                                             \
          --manifests /manifests/                                               \
          --output /db/bundles.db                                               \
    && sed -i -e 's|^#mount_program|mount_program|g'                            \
       -e '/additionalimage.*/a "/var/lib/shared",' /etc/containers/storage.conf\
   && echo

RUN set -ex                                                                     \
     && mkdir -p \
                 /var/lib/shared/overlay-images \
                 /var/lib/shared/overlay-layers \
     && touch /var/lib/shared/overlay-images/images.lock \
     && touch /var/lib/shared/overlay-layers/layers.lock \
     && sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' /etc/containers/storage.conf \
    && echo

#################################################################################
# ContainerOne | Cloud Orchestration Tools - Point of Origin
ENV varVerOpenshift="${varVerOpenshift}" varUrlGit="${varUrlGit}"
LABEL VENDOR="containercraft.io"                                                \
      NAME="Koffer"                                                             \
      BUILD_DATE="${varRunDate}"                                                \
      OpenShift="${varVerOpenshift}"                                            \
      maintainer="ContainerCraft.io"                                            \
      License=GPLv3 
ENTRYPOINT ["/usr/bin/koffer"]
WORKDIR /root/koffer