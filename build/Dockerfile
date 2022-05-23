# syntax=docker/dockerfile:1.4.1-labs
ARG TOOLCHAIN_CHANGING=false
ARG upstream_snapshot="20220521"
ARG upstream_image="gentoo/stage3:musl-${upstream_snapshot}"
ARG stage3_bootstrap="upstream"

FROM $upstream_image as upstream
ARG TOOLCHAIN_CHANGING
ARG upstream_snapshot
ARG upstream_image

SHELL [ "/bin/bash", "-euxETo", "pipefail", "-c" ]

RUN \
rm --force --recursive /var/db/repos/gentoo; \
if [[ "${TOOLCHAIN_CHANGING}" = "GCC_TO_LLVM" ]]; then \
  emerge-webrsync --revert="${upstream_snapshot}"; \
else \
  emaint sync --allrepos; \
fi; \
:;

COPY _assets/000_catalyst/etc/portage /etc/portage/

# Sync up on whatever differences exist between the tarball and the snapshot.
RUN \
--mount=type=tmpfs,target=/run \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
emerge --depclean; \
env-update; \
:;

RUN \
--mount=type=tmpfs,target=/run \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  app-eselect/eselect-repository \
  dev-vcs/git \
; \
emerge --depclean; \
env-update; \
:;

# Remove the official gentoo repo (we want the snapshot instead)
COPY ./_assets/usr/share/portage/config/repos.conf /usr/share/portage/config/repos.conf

# Remove any trace of the original gentoo repo from our cache (it is just wasting space at this point)
RUN rm --force --recursive /var/db/repos/gentoo

# Sync with the snapshot repo
RUN \
emaint sync --allrepos; \
:;

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
emerge --depclean; \
env-update; \
:;

FROM $stage3_bootstrap as seed
RUN rm --force --recursive /var/db/repos/gentoo
RUN rm --force --recursive /var/tmp/*
RUN rm /etc/portage/make.profile

FROM $stage3_bootstrap as catalyst_run

RUN \
--mount=type=tmpfs,target=/run \
emerge \
  --autounmask-write \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  dev-util/catalyst \
  sys-fs/squashfs-tools-ng \
; \
:;

COPY --from=seed / /tmp/seed

RUN \
mkdir --parent /var/tmp/catalyst/builds/; \
tar \
  --create \
  --directory=/tmp/seed \
  --file /var/tmp/catalyst/builds/seed.tar \
  . \
; \
:;

RUN \
mkdir --parent /var/tmp/catalyst/snapshots; \
cd /var/db/repos/; \
gensquashfs --pack-dir=gentoo /var/tmp/catalyst/snapshots/gentoo-snapshot.sqfs; \
:;

ARG TOOLCHAIN_CHANGING
ENV TOOLCHAIN_CHANGING="${TOOLCHAIN_CHANGING}"
COPY _assets/000_catalyst/etc/catalyst/catalyst.conf /etc/catalyst/
COPY _assets/000_catalyst/etc/catalyst/catalystrc.template /etc/catalyst/
RUN \
cd /etc/catalyst/; \
envsubst '${TOOLCHAIN_CHANGING}' < /etc/catalyst/catalystrc.template > /etc/catalyst/catalystrc; \
:;

ARG ARCH="amd64"
ARG VERSION_STAMP="clang-musl-container-bootstrap"
ARG RELEASE_TYPE="${VERSION_STAMP}"
ARG PORTAGE_SNAPSHOT="snapshot"

ENV ARCH="${ARCH}"
ENV VERSION_STAMP="${VERSION_STAMP}"
ENV RELEASE_TYPE="${RELEASE_TYPE}"
ENV PORTAGE_SNAPSHOT="${PORTAGE_SNAPSHOT}"

ENV SOURCE_SUBPATH="seed.tar"

ARG STAGE1_PROFILE="custom/linux/amd64/clang-musl-container/optimize/lto"
ENV STAGE1_PROFILE="${STAGE1_PROFILE}"

COPY _assets/000_catalyst/etc/catalyst/specs/stage1.template.spec /etc/catalyst/specs/stage1.template.spec
RUN \
cd /etc/catalyst/specs/; \
envsubst < stage1.template.spec > stage1.spec; \
:;

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/stage1.spec; \
:;

# Now that we have changed over our toolchain we don't need the changeover build params anymore
ENV TOOLCHAIN_CHANGING=false
RUN \
cd /etc/catalyst/; \
envsubst '${TOOLCHAIN_CHANGING}' < /etc/catalyst/catalystrc.template > /etc/catalyst/catalystrc; \
:;

COPY _assets/000_catalyst/etc/catalyst/specs/stage2.template.spec /etc/catalyst/specs/

ARG STAGE2_PROFILE="custom/linux/amd64/clang-musl-container/optimize/lto"
ENV STAGE2_PROFILE="${STAGE2_PROFILE}"

ENV SOURCE_SUBPATH="${VERSION_STAMP}/stage1-${ARCH}-${RELEASE_TYPE}.tar.gz"

RUN \
cd /etc/catalyst/specs/; \
envsubst < stage2.template.spec > stage2.spec; \
:;

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/stage2.spec; \
:;

ENV SOURCE_SUBPATH="${VERSION_STAMP}/stage2-${ARCH}-${RELEASE_TYPE}.tar.gz"
ENV VERSION_STAMP="clang-musl-container-bootstrapped"
ENV RELEASE_TYPE="${VERSION_STAMP}"
RUN \
cd /etc/catalyst/specs/; \
envsubst < stage2.template.spec > stage2.rebuild.spec; \
:;

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/stage2.rebuild.spec; \
:;

COPY _assets/000_catalyst/etc/catalyst/specs/stage3.template.spec /etc/catalyst/specs/
ENV SOURCE_SUBPATH="${VERSION_STAMP}/stage2-${ARCH}-${RELEASE_TYPE}.tar.gz"
ARG STAGE3_PROFILE="${STAGE2_PROFILE}"
ENV STAGE3_PROFILE="${STAGE3_PROFILE}"
RUN \
cd /etc/catalyst/specs/; \
envsubst < stage3.template.spec > stage3.spec; \
:;

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/stage3.spec; \
:;

RUN \
mkdir --parent /objective; \
tar \
  --extract \
  --file /var/tmp/catalyst/builds/clang-musl-container-bootstrapped/stage3-amd64-clang-musl-container-bootstrapped.tar.gz \
  --directory=/objective \
; \
:;

FROM scratch as objective

COPY --from=catalyst_run /objective /

SHELL [ "/bin/bash", "-euxETo", "pipefail", "-c" ]

RUN \
env-update; \
:;

# Clean up busted symlinks (baselayout dosen't seem to do a good job of accounting for env without gcc + glibc)
RUN \
find /usr/bin -xtype l -exec rm {} \; ; \
:;

# TODO: find out if we still really need this
RUN \
for binary in /usr/lib/llvm/14/bin/*; do \
  ln --symbolic --relative "${binary}" "/usr/bin/$(basename "${binary}")"; \
done; \
:;

# TODO: find out if we still really need this
RUN \
for library in /usr/lib/llvm/14/lib/*.{so,a} /usr/lib/llvm/14/lib/*.{so,a}.*; do \
  if [[ -e "/usr/lib/$(basename "${library}")" ]]; then \
    rm "/usr/lib/$(basename "${library}")"; \
  fi; \
  ln --symbolic --relative "${library}" "/usr/lib/$(basename "${library}")"; \
done; \
:;

# Declare clang{,++} to be the default C{,++} compiler
RUN \
ln --symbolic --relative "/usr/bin/clang" "/usr/bin/cc"; \
ln --symbolic --relative "/usr/bin/clang++" "/usr/bin/c++"; \
:;

COPY ./_assets/usr/share/portage/config/repos.conf /usr/share/portage/config/repos.conf

COPY --from=upstream /var/db/repos/gentoo /var/db/repos/gentoo
# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
emerge --depclean; \
env-update; \
:;

## TODO: add dev-vcs/git to @system in repo upstream
#RUN \
#--mount=type=tmpfs,target=/run \
#emerge \
#  --complete-graph \
#  --deep \
#  --jobs="$(nproc)" \
#  --load-average="$(($(nproc) * 2))" \
#  --newuse \
#  --update \
#  --verbose \
#  --with-bdeps=y \
#  dev-vcs/git \
#; \
#emerge --depclean; \
#env-update; \
#:;
#
#
## Package up everything!
#RUN \
#--mount=type=tmpfs,target=/run \
#emerge \
#  --build-pkg \
#  --complete-graph \
#  --deep \
#  --empty-tree \
#  --jobs="$(nproc)" \
#  --load-average="$(($(nproc) * 2))" \
#  --newuse \
#  --update \
#  --verbose \
#  --with-bdeps=y \
#  @world \
#; \
#:;
