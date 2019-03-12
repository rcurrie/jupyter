FROM tensorflow/tensorflow:1.13.1-gpu-py3-jupyter

ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
