FROM tensorflow/tensorflow:2.0.0b0-py3-jupyter

# Tensorflow dockers do not contain git which we use for
# installing python packages directly from github via pip
RUN apt-get update && apt-get install -y --no-install-recommends \
  git wget

RUN pip install --upgrade pip

RUN pip install --force-reinstall \
  http://public.gi.ucsc.edu/~rcurrie/tensorflow-2.0.0b0-cp36-cp36m-linux_x86_64.whl

RUN pip install torch==1.1.0 -f https://download.pytorch.org/whl/cpu/stable

ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
