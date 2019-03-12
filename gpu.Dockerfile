FROM tensorflow/tensorflow:1.13.1-gpu-py3-jupyter

# Tensorflow dockers do not contain git which we use for
# installing python packages directly from github via pip
RUN apt-get update && apt-get install -y --no-install-recommends \
  git wget

ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
