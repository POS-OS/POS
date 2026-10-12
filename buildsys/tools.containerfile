# The build tools of a build: the Fedora packages its steps declare
# (host-requires, prepare-requires) and rpm-build, installed once on a
# pinned base when the build is created (buildsys/build.sh: tools_build).
# Every step runs in a container of it; nothing in it is under /pos, and a
# package build has its own /pos mounted read-only.
ARG BASE
FROM $BASE
ARG PACKAGES
RUN dnf -y install --setopt=install_weak_deps=False $PACKAGES && dnf clean all
