FROM ros:jazzy-ros-base-noble AS base

# Install basic dev tools (And clean apt cache afterwards)
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
        apt-get -y --quiet --no-install-recommends install \
        # Download tool
        curl \
        # Install Zenoh ROS2 RMW
        ros-"$ROS_DISTRO"-rmw-zenoh-cpp \
    && rm -rf /var/lib/apt/lists/*

# Setup ROS workspace folder
ENV ROS_WS=/opt/ros_ws
WORKDIR $ROS_WS

# Setup Zenoh ROS2 RMW
ENV RMW_IMPLEMENTATION=rmw_zenoh_cpp

# Enable ROS log colorised output
ENV RCUTILS_COLORIZED_OUTPUT=1

# Clone Humble Dataspeed repos, to be compiled in Jazzy
RUN git clone https://bitbucket.org/DataspeedInc/dataspeed_can.git $ROS_WS/src/ \
 && git clone https://bitbucket.org/DataspeedInc/dbw_ros.git $ROS_WS/dbw_ros

# Move to src only necessary pkgs
RUN mv $ROS_WS/dbw_ros/dbw1/dataspeed_* $ROS_WS/src/ \
 && mv $ROS_WS/dbw_ros/dbw1/dbw_ford_* $ROS_WS/src/

# Install dependencies via rosdep
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
        rosdep install --from-paths src --ignore-src -r -y \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------

FROM base AS prebuilt

# Import Five DBW code into docker image
COPY av_dbw_launch $ROS_WS/src/

# Source ROS setup for dependencies and build our code
RUN . /opt/ros/"$ROS_DISTRO"/setup.sh \
    && colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release

# -----------------------------------------------------------------------

FROM base AS dev

# Install basic dev tools (And clean apt cache afterwards)
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive \
        apt-get -y --quiet --no-install-recommends install \
        # Command-line editor
        nano \
        # Ping network tools
        inetutils-ping \
        # Bash auto-completion for convenience
        bash-completion \
    && rm -rf /var/lib/apt/lists/*

# Add sourcing local workspace command to bashrc when running interactively
# Add colcon build alias for convenience
RUN echo "source /opt/ros/$ROS_DISTRO/setup.bash" >> /root/.bashrc && \
    echo 'alias colcon_build="colcon build --symlink-install \
            --cmake-args -DCMAKE_BUILD_TYPE=Release && \
            source install/setup.bash"' >> /root/.bashrc

# Enter bash for development
CMD ["bash"]

# -----------------------------------------------------------------------

FROM base AS runtime

# Copy artifacts/binaries from prebuilt
COPY --from=prebuilt $ROS_WS/install $ROS_WS/install

# Add command to docker entrypoint to source newly compiled code in container
RUN sed --in-place --expression \
      "\$isource \"$ROS_WS/install/setup.bash\" " \
      /ros_entrypoint.sh

# Launch Five DBW launchfile
CMD ["ros2", "launch", "av_dbw_launch", "av_dbw.launch.xml"]
