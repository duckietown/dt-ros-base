ARG ARCH=arm32v7
ARG ROS_DISTRO=melodic
ARG OS_DISTRO=bionic
ARG BASE_TAG=${ROS_DISTRO}-ros-base-${OS_DISTRO}

FROM ${ARCH}/ubuntu:${OS_DISTRO}

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
ENV ROS_INSTALL_DIR /opt/ros/${ROS_DISTRO}
ENV ROS_SRC_DIR /ros_ws/${ROS_DISTRO}

# copy QEMU
COPY ./assets/qemu/${ARCH}/ /usr/bin/

# install apt dependencies
COPY ./dependencies-apt.txt /tmp/dependencies-apt.txt
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    $(awk -F: '/^[^#]/ { print $1 }' /tmp/dependencies-apt.txt | uniq) \
  && rm -rf /var/lib/apt/lists/*

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

# fix deprecated yaml loader in wstool
RUN sed \
  -i \
  's/yamldata = yaml.load(stream)/yamldata = yaml.load(stream, Loader=yaml.FullLoader)/' \
  /usr/local/lib/python3.6/dist-packages/wstool/config_yaml.py

# remove dependencies files
RUN rm /tmp/dependencies*

# initialize rosdep
RUN rosdep init && rosdep update

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
RUN mkdir -p ${ROS_SRC_DIR}
RUN \
  set -ex; \
  cd ${ROS_SRC_DIR}; \
  catkin config \
    --init \
    -DCMAKE_BUILD_TYPE=Release \
    --install-space ${ROS_INSTALL_DIR} \
    --install; \
  wstool init \
    -j $(nproc) \
    src; \
  set +ex

# install utility scripts
COPY assets/scripts/* /usr/local/bin/

# build ROS packages
COPY packages-ros.txt /tmp/packages-ros.txt
RUN \
  set -ex; \
  cd ${ROS_SRC_DIR}; \
  PACKAGES=$(sed -e '/#[ ]*BLACKLIST/,$d' /tmp/packages-ros.txt | sed "/^#/d" | uniq | sed -z "s/\n/ /g"); \
  HAS_PACKAGES=$(echo $PACKAGES | sed '/^\s*#/d;/^\s*$/d' | wc -l); \
  if [ $HAS_PACKAGES -eq 1 ]; then \
    # merge ROS packages into the current workspace
    dt_analyze_packages /tmp/packages-ros.txt; \
    # replace python -> python3 in all the shebangs of the packages
    dt_py2to3; \
    # blacklist packages
    dt_blacklist_packages /tmp/packages-ros.txt; \
    # install dependencies (replacing python -> python3, excluding libboost)
    dt_install_dependencies ./src; \
    # build and clean
    dt_build_ros_packages; \
  fi; \
  set +ex

# configure command
CMD ["bash"]

# define maintainer
LABEL maintainer="Andrea F. Daniele (afdaniele@ttic.edu)"
