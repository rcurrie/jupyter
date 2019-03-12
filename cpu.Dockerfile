FROM jupyter/tensorflow-notebook:7f1482f5a136

# Match tensorflow in image we run on k8s PRP
RUN pip uninstall -y keras
RUN pip install --no-cache-dir tensorflow==1.13.1

ADD requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
