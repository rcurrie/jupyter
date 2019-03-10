build:
	# Build image for local jupyter server w/o GPU
	docker build -f cpu.Dockerfile -t $(USER)-jupyter .
	docker tag $(USER)-jupyter robcurrie/jupyter
	docker push robcurrie/jupyter
	# Build image for runing on k8s cluster with a GPU
	docker build -f gpu.Dockerfile -t $(USER)-jupyter-gpu .
	docker tag $(USER)-jupyter-gpu robcurrie/jupyter-gpu
	docker push robcurrie/jupyter-gpu

generate-ca:
	# See https://juno.sh/ssl-self-signed-cert/
	# wget https://juno.sh/assets/openssl.cnf
	# then edit [ alt_names ] to DNS.1 = your.server.domain
	rm -rf ca
	mkdir ca ca/certs ca/crl ca/newcerts ca/private
	chmod 700 ca/private
	touch ca/index.txt
	echo 1000 > ca/serial
	openssl genrsa -out ca/private/ca.key.pem 4096
	chmod 400 ca/private/ca.key.pem
	openssl req -config openssl.cnf \
		-nodes \
		-key ca/private/ca.key.pem \
		-new -x509 -days 365 -sha256 -extensions v3_ca \
		-out ca/certs/ca.cert.pem
	chmod 444 ca/certs/ca.cert.pem

generate-ssl:
	rm -rf ssl
	mkdir ssl ssl/csr ssl/certs ssl/private
	chmod 700 ssl/private
	openssl genrsa -out ssl/private/ssl.key.pem 2048
	chmod 400 ssl/private/ssl.key.pem
	openssl req -config openssl.cnf \
		-nodes \
		-key ssl/private/ssl.key.pem \
		-new -sha256 -out ssl/csr/ssl.csr.pem
	openssl ca -config openssl.cnf \
		-extensions server_cert -days 1024 -notext -md sha256 \
		-in ssl/csr/ssl.csr.pem \
		-out ssl/certs/ssl.cert.pem
	chmod 444 ssl/certs/ssl.cert.pem

jupyter:
	# Run a local jupyter server with password mapping your
	# home directory directly into the docker, exposing jupyter
	# and tensorboard ports and setting the environment to support
	# access to S3
	docker run --rm -it --name $(USER)-jupyter \
		--user=`id -u`:`id -g` \
		--network=$(USER)-network \
		-e DEBUG=True \
		-e AWS_PROFILE="prp" \
		-e AWS_S3_ENDPOINT="https://s3.nautilus.optiputer.net" \
		-e S3_ENDPOINT="s3.nautilus.optiputer.net" \
		-p 52820:8888 \
		-v `readlink -f ~`:/home/jovyan \
		-v `readlink -f ~/.empty`:/home/jovyan/.local \
		-v `readlink -f ~/data`:/home/jovyan/data \
		-v /public/groups/braingeneers:/public/groups/braingeneers \
		--shm-size=64G --memory=128G --cpus="8" \
		$(USER)-jupyter:latest start-notebook.sh \
		--NotebookApp.certfile=/home/jovyan/jupyter/ssl/certs/ssl.cert.pem \
		--NotebookApp.keyfile=/home/jovyan/jupyter/ssl/private/ssl.key.pem \
		--ip=0.0.0.0 \
		--NotebookApp.password=$(JUPYTER_PASSWORD)

update-secrets:
	# Update secrets from our AWS file so we can access S3 in k8s
	kubectl delete secrets/s3-credentials
	kubectl create secret generic s3-credentials --from-file=../.aws/credentials

run: create-pod run-python-on-pod delete-pod

list-pods:
	# List all pods
	kubectl get pods

describe-pod:
	# Describe an allocated and running pod ie where is it...
	kubectl describe pod/$(USER)-pod

create-pod:
	# Create a pod 
	envsubst < pod.yml | kubectl create -f -
	kubectl wait --for=condition=Ready pod/$(USER)-pod --timeout=5m

delete-pod:
	# Delete a pod
	envsubst < pod.yml | kubectl delete -f -
	kubectl wait --for=delete pod/$(USER)-pod --timeout=5m

monitor:
	# Run nvidia monitor in a loop to monitor GPU usage
	kubectl exec -it $(USER)-pod -- nvidia-smi --loop=5

shell:
	# Open a shell on the pod
	kubectl exec -it $(USER)-pod /bin/bash

run-notebook:
	# Run a notebook on the command line with no timeout inside the local jupyter instance
	docker exec -it -e DEBUG=False $(USER)-jupyter \
		jupyter nbconvert --ExecutePreprocessor.timeout=None --to notebook \
		--execute $(NOTEBOOK) --output $(notdir $(NOTEBOOK))

run-notebook-on-pod:
	# Run a long running notebook on the command line inside jupyter
	# NOTE: You will not see any print() output, converting to .py below
	# may be better
	kubectl cp ~/$(NOTEBOOK) $(USER)-pod:/notebooks
	kubectl exec -it $(USER)-pod -- \
		jupyter nbconvert --ExecutePreprocessor.timeout=None --to notebook \
		--execute $(notdir $(NOTEBOOK))  --output $(notdir $(NOTEBOOK))
	kubectl cp $(USER)-pod:/notebooks/$(notdir $(NOTEBOOK)) ~/$(NOTEBOOK)

run-python-on-pod:
	# Convert notbook to .py, run on pod, backhaul model
	kubectl cp ~/$(NOTEBOOK) $(USER)-pod:/notebooks
	kubectl exec -it $(USER)-pod -- \
		jupyter nbconvert --to python \
		--output /notebooks/$(notdir $(NOTEBOOK)).py /notebooks/$(notdir $(NOTEBOOK))
	time kubectl exec -it $(USER)-pod -- bash -c 'cd /notebooks && \
		python3 $(notdir $(NOTEBOOK)).py 2>&1 | tee log.txt'

create-job:
	envsubst < job.yml | kubectl create -f -

delete-job:
	envsubst < job.yml | kubectl delete -f -

log-job:
	kubectl logs -f job/$(USER)-job

run-notebook-in-job:
	# Copy the notebook to S3 so the job can pick it up from there
	aws --profile prp --endpoint https://s3.nautilus.optiputer.net \
		s3 cp ~/$(NOTEBOOK) s3://braingeneers/$(USER)/$(NOTEBOOK)
	# Start the job (see job.yml for details on how it runs the notebook)
	envsubst < job.yml | kubectl create -f -
	# Wait till its running
	# kubectl wait --for=condition=complete job/$(USER)-job  --timeout=5m

pull-notebook-back:
	# Copy the notebook as run on the job back locally - reload in browser to see
	aws --profile prp --endpoint https://s3.nautilus.optiputer.net \
		s3 cp s3://braingeneers/$(USER)/$(NOTEBOOK)  ~/$(NOTEBOOK)
