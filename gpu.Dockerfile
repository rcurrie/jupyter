# Try and match the cpu version we're using
FROM tensorflow/tensorflow:1.12.0-gpu-py3-jupyter

# RUN apt-get update -y && apt-get install -y --no-install-recommends \
#     git wget vim \
#     && apt-get clean \
#     && rm -rf /var/lib/apt/lists/*

ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
