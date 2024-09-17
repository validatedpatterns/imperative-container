FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

ARG TITLE="imperative-container"
ARG DESCRIPTION="Imperative Container"
ARG MAINTAINER="Validated Patterns <team-validated-patterns@redhat.com>"
# https://spdx.org/licenses/
ARG LICENSE="Apache-2.0"
ARG URL="https://github.com/validatedpatterns"
ARG SOURCE="https://github.com/validatedpatterns/imperative-container/blob/main/Containerfile"

# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
LABEL org.opencontainers.image.title="${TITLE}" \
      org.opencontainers.image.description="${DESCRIPTION}" \
      org.opencontainers.image.url="${URL}" \
      org.opencontainers.image.source="${SOURCE}" \
      org.opencontainers.image.authors="${MAINTAINER}" \
      org.opencontainers.image.licenses="${LICENSE}" \
      name="${TITLE}" \
      maintainer="${MAINTAINER}" \
      license="${LICENSE}" \
      description="${DESCRIPTION}"

ARG DNF_TO_REMOVE="dejavu-sans-fonts langpacks-core-font-en langpacks-core-en langpacks-en tar"
ARG RPM_TO_FORCEFULLY_REMOVE="cracklib-dicts"
# Versions
ARG OPENSHIFT_CLIENT_VERSION="4.16.10"

# As of 9/5/2024: awxkit is not compatible with python 3.12 due to setuptools
# Ansible-core 2.16 is needed for losing track of async jobs (as noted in AGOF for infra.controller_configuration)
# 'pip' will be influenced by where /usr/bin/python3 points, which we take care of with the altnernatives
# command
ARG PYTHON_VERSION="3.11"
ARG PYTHON_PKGS="python${PYTHON_VERSION} python${PYTHON_VERSION}-pip python3-pip"
ARG ANSIBLE_CORE_SPEC="ansible-core==2.16.*"
ARG YQ_VERSION="4.40.7"

# amd64 - arm64
ARG TARGETARCH
# x86_64 - aarch64
ARG ALTTARGETARCH
# '' - arm64-
ARG OPTTARGETARCH
# Extra rpms for specific arches. Needed because on arm64 pip insists on rebuilding psutils
ARG EXTRARPMS

USER root

# 'pip' is expected to be the pip resolved by 'python3 pip' AKA the one we install with PYTHON_VERSION
RUN microdnf --disableplugin=subscription-manager install -y ${PYTHON_PKGS} && microdnf --disableplugin=subscription-manager clean all
RUN alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 0

# Add requirements.yml file for ansible collections
COPY requirements.yml /tmp/requirements.yml

RUN microdnf --disableplugin=subscription-manager install -y make git-core tar jq which findutils diffutils sshpass $EXTRARPMS && \
curl -sLfO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_CLIENT_VERSION}/openshift-client-linux-${OPTTARGETARCH}${OPENSHIFT_CLIENT_VERSION}.tar.gz && \
tar xvf openshift-client-linux-${OPTTARGETARCH}${OPENSHIFT_CLIENT_VERSION}.tar.gz -C /usr/local/bin && \
rm -rf openshift-client-linux-${OPTTARGETARCH}${OPENSHIFT_CLIENT_VERSION}.tar.gz  && rm -f /usr/local/bin/kubectl && ln -sf /usr/local/bin/oc /usr/local/bin/kubectl && \
curl -sSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${TARGETARCH} && chmod 755 /usr/local/bin/yq && \
rm -rf /root/anaconda* /root/original-ks.cfg /usr/local/README && \
microdnf remove -y $DNF_TO_REMOVE && \
rpm -e --nodeps $RPM_TO_FORCEFULLY_REMOVE && \
microdnf clean all && \
rm -rf /var/cache/dnf

#USER 1001
ENV HOME=/pattern-home
ENV ANSIBLE_REMOTE_TMP=/pattern-home/.ansible/tmp
ENV ANSIBLE_ASYNC_DIR=/tmp/.ansible/.async
ENV ANSIBLE_LOCAL_TMP=/pattern-home/.ansible/tmp
ENV ANSIBLE_LOCALHOST_WARNING=False
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Add requirements.yml file for ansible collections
COPY requirements.yml /tmp/requirements.yml
COPY requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt && \
ansible-galaxy collection install --collections-path /usr/share/ansible/collections -r /tmp/requirements.yml && \
if [ -n "$EXTRARPMS" ]; then microdnf remove -y $EXTRARPMS; fi && \
mkdir -p /pattern/.ansible/tmp /pattern-home/.ansible/tmp && \
find /pattern/.ansible -type d -exec chmod 770 "{}" \; && \
find /pattern-home/.ansible -type d -exec chmod 770 "{}" \;

COPY default-cmd.sh /usr/local/bin
WORKDIR /pattern
CMD ["/usr/local/bin/default-cmd.sh"]
