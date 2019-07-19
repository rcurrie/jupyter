FROM tensorflow/tensorflow:2.0.0b0-gpu-py3-jupyter

# Tensorflow dockers do not contain git which we use for
# installing python packages directly from github via pip
RUN apt-get update && apt-get install -y --no-install-recommends \
  git wget \
  libopenmpi-dev \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip

RUN pip install torch==1.1.0 -f https://download.pytorch.org/whl/cu100/stable

ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
