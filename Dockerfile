# parameters
ARG REPO_NAME="dt-ros-base"

ARG ARCH=arm32v7
ARG ROS_DISTRO=melodic
ARG OS_DISTRO=bionic
ARG BASE_TAG=${ROS_DISTRO}-ros-base-${OS_DISTRO}

FROM ${ARCH}/ubuntu:${OS_DISTRO}

ARG REPO_NAME
ARG ARCH
ARG ROS_DISTRO
ARG OS_DISTRO

# setup environment
ENV INITSYSTEM off
ENV QEMU_EXECVE 1
ENV TERM "xterm"
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV PYTHONIOENCODING UTF-8
ENV ROS_PYTHON_VERSION 3
ENV DEBIAN_FRONTEND noninteractive
ENV ROS_DISTRO "${ROS_DISTRO}"
ENV OS_DISTRO "${OS_DISTRO}"
ENV ROS_INSTALL_DIR /opt/ros/${ROS_DISTRO}/
ENV ROS_SRC_DIR /ros_ws

# copy QEMU
COPY ./assets/qemu/${ARCH}/ /usr/bin/

# add python3.7 sources to APT
# RUN echo "deb http://ppa.launchpad.net/deadsnakes/ppa/ubuntu xenial main" >> /etc/apt/sources.list
# RUN echo "deb-src http://ppa.launchpad.net/deadsnakes/ppa/ubuntu xenial main" >> /etc/apt/sources.list
# RUN gpg --keyserver keyserver.ubuntu.com --recv 6A755776 \
#  && gpg --export --armor 6A755776 | apt-key add -

# install apt dependencies
COPY ./dependencies-apt.txt /tmp/dependencies-apt.txt
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    $(awk -F: '/^[^#]/ { print $1 }' /tmp/dependencies-apt.txt | uniq) \
  && rm -rf /var/lib/apt/lists/*

# update alternatives for python, python3
# RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.7 1
# RUN update-alternatives --install /usr/bin/python3 python /usr/bin/python3.7 1

# install pip3
RUN cd /tmp \
  && wget --no-check-certificate http://bootstrap.pypa.io/get-pip.py \
  && python3 ./get-pip.py \
  && rm ./get-pip.py

# install python dependencies
COPY ./dependencies-py3.txt /tmp/dependencies-py3.txt
RUN pip3 install -r /tmp/dependencies-py3.txt

# configure catkin to work nicely with docker
RUN sed \
  -i \
  's/__default_terminal_width = 80/__default_terminal_width = 160/' \
  /usr/local/lib/python3.6/dist-packages/catkin_tools/common.py

# remove dependencies files
RUN rm /tmp/dependencies*

# RPi libs
ADD assets/vc.tgz /opt/
COPY assets/00-vmcs.conf /etc/ld.so.conf.d
RUN ldconfig

# initialize rosdep
RUN rosdep init && rosdep update

# setup environment and install dependencies
# RUN pip3 install -U -f https://extras.wxpython.org/wxPython4/extras/linux/gtk3/ubuntu-18.04 wxPython

# build libboost for Python3
RUN cd /usr/src \
  && wget --no-verbose https://dl.bintray.com/boostorg/release/1.65.1/source/boost_1_65_1.tar.gz \
  && tar xzf boost_1_65_1.tar.gz \
  && cd boost_1_65_1 \
  && ln -s /usr/local/include/python3.6m /usr/local/include/python3.6 \
  && ./bootstrap.sh --with-python=$(which python3) \
  && echo ">> Building libboost..." \
  && ./b2 -j $(nproc) install > /dev/null \
  && echo "<< Finished libboost." \
  && rm /usr/local/include/python3.6 \
  && ldconfig \
  && cd / \
  && rm -rf /usr/src/*

# create a workspace where we can build ROS
ARG ROS_PKGS_SRC_DIR="${ROS_SRC_DIR}/${REPO_NAME}/"
RUN mkdir -p ${ROS_PKGS_SRC_DIR}
WORKDIR ${ROS_PKGS_SRC_DIR}
RUN catkin \
  config \
    --init \
    -DCMAKE_BUILD_TYPE=Release \
    --install-space ${ROS_INSTALL_DIR} \
    --install

# setup ROS install
RUN rosinstall_generator \
  ros_comm \
    --rosdistro melodic \
    --deps \
    --tar > ros-melodic.rosinstall \
  && wstool \
    init \
    -j $(nproc) \
    src \
    ros-melodic.rosinstall \
  && rm ros-melodic.rosinstall

# install utility scripts
COPY assets/scripts/* /usr/local/bin/

# analyze additional ROS packages
COPY packages-ros.txt /tmp/packages-ros.txt
RUN \
  set -e; \
  PACKAGES=$(sed -e '/#[ ]*BLACKLIST/,$d' /tmp/packages-ros.txt | sed "/^#/d" | uniq); \
  NUM_PACKAGES=$(echo $PACKAGES | sed '/^\s*#/d;/^\s*$/d' | wc -l); \
  if [ $NUM_PACKAGES -ge 1 ]; then \
    # merge ROS packages into the current workspace
    dt_analyze_packages /tmp/packages-ros.txt; \
    # replace python -> python3 in all the shebangs of the packages
    dt_py2to3; \
    # blacklist ROS packages
    SKIP_BLACKLIST=$(grep -q "BLACKLIST" /tmp/packages-ros.txt && echo $?); \
    if [ "${SKIP_BLACKLIST}" -eq 0 ]; then \
      BLACKLIST=$(sed -e "1,/#[ ]*BLACKLIST/d" /tmp/packages-ros.txt | sed "/^#/d" | uniq); \
      catkin config \
        --append-args \
        --blacklist $BLACKLIST; \
    fi; \
  fi; \
  set +e

# install dependencies for ROS packages
RUN \
  # install all python dependencies (replacing python -> python3)
  dt_install_dependencies --python-deps; \
  # install all non-python dependencies (exclude libboost, we build it from source for python3)
  dt_install_dependencies --no-python-deps;

# build ROS (and additional packages)
RUN catkin build \
  && catkin clean -y \
    --logs

# change working dir
WORKDIR /root

# configure command
CMD ["bash"]

# define maintainer
LABEL maintainer="Andrea F. Daniele (afdaniele@ttic.edu)"
