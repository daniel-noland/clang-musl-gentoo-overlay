# syntax=docker/dockerfile:1.4.1-labs
ARG upstream_snapshot="20220514"
ARG seed_image="gentoo/stage3:musl-${upstream_snapshot}"

FROM $seed_image as seed_build
ARG upstream_snapshot
ARG seed_image

SHELL [ "/bin/bash", "-euxETo", "pipefail", "-c" ]

RUN \
emerge-webrsync --revert="${upstream_snapshot}"; \
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

FROM seed_build as seed
RUN rm --force --recursive /var/db/repos/gentoo
RUN rm --force --recursive /var/tmp/*
RUN rm /etc/portage/make.profile

FROM seed_build as catalyst_run

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

COPY _assets/000_catalyst/etc/catalyst/catalyst.conf /etc/catalyst/
COPY _assets/000_catalyst/etc/catalyst/catalystrc /etc/catalyst
COPY _assets/000_catalyst/etc/catalyst/specs/bootstrap/stage1.spec /etc/catalyst/specs/bootstrap/stage1.spec

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrap/stage1.spec; \
:;

#COPY _assets/001_catalyst/etc/catalyst/catalystrc /etc/catalyst
COPY _assets/000_catalyst/etc/catalyst/specs/bootstrap/stage2.spec /etc/catalyst/specs/bootstrap/stage2.spec

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrap/stage2.spec; \
:;

COPY _assets/000_catalyst/etc/catalyst/specs/bootstrap/stage3.spec /etc/catalyst/specs/bootstrap/stage3.spec

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrap/stage3.spec; \
:;

# ^^^ toolchain change line in the sand ^^^

RUN \
mkdir --parent /tmp/bootstrap-stage3; \
tar \
  --extract \
  --file /var/tmp/catalyst/builds/clang-musl-container-bootstrap/stage3-amd64-clang-musl-container-bootstrap.tar.gz \
  --directory=/tmp/bootstrap-stage3 \
; \
:;

FROM scratch as bootstrap_objective

COPY --from=catalyst_run /tmp/bootstrap-stage3 /

SHELL [ "/bin/bash", "-euxETo", "pipefail", "-c" ]

RUN \
env-update; \
:;

# Clean up busted symlinks (baselayout dosen't do a good job of accounting for env without gcc + glibc)
RUN \
find /usr/bin -xtype l -exec rm {} \; ; \
:;

RUN \
for binary in /usr/lib/llvm/14/bin/*; do \
  ln --symbolic --relative "${binary}" "/usr/bin/$(basename "${binary}")"; \
done; \
:;

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

FROM catalyst_run as catalyst_run_2

COPY --from=bootstrap_objective / /tmp/bootstrap_objective

RUN \
tar \
 --create \
 --directory=/tmp/bootstrap_objective \
 --file /var/tmp/catalyst/builds/bootstrap.tar \
 . \
; \
:;

COPY _assets/001_catalyst/etc/catalyst/catalystrc /etc/catalyst/
COPY _assets/001_catalyst/etc/catalyst/specs/bootstrapped/stage1.spec /etc/catalyst/specs/bootstrapped/

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrapped/stage1.spec; \
:;

COPY _assets/001_catalyst/etc/catalyst/specs/bootstrapped/stage2.spec /etc/catalyst/specs/bootstrapped/

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrapped/stage2.spec; \
:;

COPY _assets/001_catalyst/etc/catalyst/specs/bootstrapped/stage3.spec /etc/catalyst/specs/bootstrapped/

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
catalyst --file /etc/catalyst/specs/bootstrapped/stage3.spec; \
:;

RUN \
mkdir --parent /tmp/output; \
tar \
  --extract \
  --file /var/tmp/catalyst/builds/clang-musl-container-optimized/stage3-amd64-clang-musl-container-optimized.tar.gz \
  --directory=/tmp/output \
; \
:;

FROM scratch as output
COPY --from=catalyst_run_2 /tmp/output /
SHELL [ "/bin/bash", "-euxETo", "pipefail", "-c" ]

RUN \
for binary in /usr/lib/llvm/14/bin/*; do \
  ln --symbolic --relative "${binary}" "/usr/bin/$(basename "${binary}")"; \
done; \
:;

RUN \
for library in /usr/lib/llvm/14/lib/*.{so,a} /usr/lib/llvm/14/lib/*.{so,a}.*; do \
  if [[ -e "/usr/lib/$(basename "${library}")" ]]; then \
    rm "/usr/lib/$(basename "${library}")"; \
  fi; \
  ln --symbolic --relative "${library}" "/usr/lib/$(basename "${library}")"; \
done; \
:;

RUN \
find /usr/bin -xtype l -exec rm {} \; ; \
ln --symbolic --relative "/usr/bin/clang" "/usr/bin/cc"; \
ln --symbolic --relative "/usr/bin/clang++" "/usr/bin/c++"; \
:;

# Download and build the kernel with a custom configuration.
# The resulting debs will bin included in the generated debian repo.
ENV KERNEL_VERSION="5.15.37"
RUN \
mkdir /tmp/linux-build/; \
wget \
  --quiet \
  --output-document=- \
  "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION}.tar.gz" \
  | \
  tar --extract --gzip --directory=/tmp/linux-build/ \
; \
cd /tmp/linux-build/linux-${KERNEL_VERSION}; \
:;

COPY _assets/002_kernel/kernel.config /tmp/linux-build/linux-${KERNEL_VERSION}/.config

WORKDIR /tmp/linux-build/linux-${KERNEL_VERSION}

COPY --from=catalyst_run /var/db/repos/gentoo/ /var/db/repos/gentoo/

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
:;

RUN \
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
  sys-kernel/gentoo-sources \
; \
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
  @world \
; \
:;

RUN \
emerge --depclean; \
env-update; \
:;

RUN emerge vim

COPY _assets/002_kernel/etc/portage/make.conf /etc/portage/

VOLUME ["/var/cache/pkg"]

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
  --buildpkg \
  --emptytree \
  @world \
; \
:;

RUN \
make \
  LLVM=1 \
  CC=clang \
  KCFLAGS="-O3 -march=native -flto=thin" \
  ARCH=x86_64 \
  --jobs="$(( "$(nproc)" + 1 ))" \
; \
:;
