FROM tensorflow/tensorflow:1.12.0-rc2-gpu-py3

RUN apt-get update -y && apt-get install -y --no-install-recommends \
    git wget vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
