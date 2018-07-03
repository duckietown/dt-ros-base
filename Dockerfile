FROM arm32v7/ros:kinetic-ros-base-xenial

MAINTAINER Breandan Considine breandan.considine@nutonomy.com

# switch on systemd init system in container
ENV INITSYSTEM off
ENV QEMU_EXECVE 1
# setup environment
ENV TERM "xterm"
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV ROS_DISTRO kinetic

COPY ./bin/ /usr/bin/

RUN [ "cross-build-start" ]

# install packages
RUN apt-get update && apt-get install -q -y \
		dirmngr \
		gnupg2 \
		sudo \
		apt-utils \
		apt-file \
		locales \
		locales-all \
		i2c-tools \
		net-tools \
		iputils-ping \
		man \
		ssh \
		htop \
		atop \
		iftop \
		less \
		lsb-release \
    && rm -rf /var/lib/apt/lists/*

# setup keys
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 421C365BD9FF1F717815A3895523BAEEB01FA116

# setup sources.list
RUN echo "deb http://packages.ros.org/ros/ubuntu `lsb_release -sc` main" > /etc/apt/sources.list.d/ros-latest.list

# install additional ros packages
RUN apt-get update && apt-get install -y \
		ros-kinetic-robot \
		ros-kinetic-perception \
		ros-kinetic-navigation \
		ros-kinetic-robot-localization \
		ros-kinetic-roslint \
		ros-kinetic-hector-trajectory-server \
		ros-kinetic-joystick-drivers \
	&& rm -rf /var/lib/apt/lists/*

# RPi libs
ADD vc.tgz /opt/
COPY 00-vmcs.conf /etc/ld.so.conf.d
RUN ldconfig

RUN [ "cross-build-end" ]

# setup entrypoint
COPY ./ros_entrypoint.sh /

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
