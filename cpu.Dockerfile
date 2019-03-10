FROM jupyter/tensorflow-notebook:7f1482f5a136

# # Install any other system packages we need
# RUN apt-get update -y && apt-get install -y --no-install-recommends \
#     git wget vim \
#     && apt-get clean \
#     && rm -rf /var/lib/apt/lists/*

# To match tensorflow/tensorflow:1.13.1-gpu-py3-jupyter which
# we'll run on PRP k8s
# RUN pip uninstall -y keras
# RUN pip install --no-cache-dir tensorflow==1.13.1

# Install custom libraries
ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
