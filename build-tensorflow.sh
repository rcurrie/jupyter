docker pull tensorflow/tensorflow:devel-py3
docker run -it -w /tensorflow \
  -v `pwd`:/mnt \
  -e HOST_PERMS="$(id -u):$(id -g)" \
  tensorflow/tensorflow:devel-py3 bash

# Then from inside the container...
# cd /tensorflow_src
# git fetch --all
# git checkout v2.0.0-beta0
# wget https://github.com/bazelbuild/bazel/releases/download/0.23.0/bazel-0.23.0-installer-linux-x86_64.sh
# chmod +x bazel-0.23.0-installer-linux-x86_64.sh
# ./bazel-0.23.0-installer-linux-x86_64.sh
# ./configure
# bazel build --jobs=8 --config=opt //tensorflow/tools/pip_package:build_pip_package
# ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp
#
# And then copy the whl that is in /tmp to the host using docker cp...
