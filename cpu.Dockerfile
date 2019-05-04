FROM tensorflow/tensorflow:2.0.0a0-py3-jupyter

# Tensorflow dockers do not contain git which we use for
# installing python packages directly from github via pip
RUN apt-get update && apt-get install -y --no-install-recommends \
  git wget

ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt

RUN pip install --force-reinstall \
  http://public.gi.ucsc.edu/~rcurrie/tensorflow-2.0.0a0-cp35-cp35m-linux_x86_64.whl
