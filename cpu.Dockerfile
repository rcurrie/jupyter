# FROM tensorflow/tensorflow:1.12.0-devel-py3
FROM jupyter/tensorflow-notebook:83ed2c63671f

# Build for local machine architecture (so we work with or without AVX)
# WORKDIR /tensorflow
# RUN ./configure && \
# 	bazel build --jobs 8 --config=opt //tensorflow/tools/pip_package:build_pip_package
# RUN bazel-bin/tensorflow/tools/pip_package/build_pip_package /root

# WORKDIR /root
# RUN pip install --upgrade /root/tensorflow-*.whl

# # Install any other system packages we need
# RUN apt-get update -y && apt-get install -y --no-install-recommends \
#     git wget vim \
#     && apt-get clean \
#     && rm -rf /var/lib/apt/lists/*

# Install custom libraries
ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

# WORKDIR /notebooks
# ENV HOME /notebooks
