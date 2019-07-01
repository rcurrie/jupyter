# Override these to for you're own use via:
# JUPYTER_PORT=1234 make jupyter
JUPYTER_PORT ?= 52820
DOCKERHUB_ACCOUNT ?= "robcurrie"

build:
	# Build image for local jupyter server w/o GPU and push
	docker build -f cpu.Dockerfile -t $(USER)-jupyter .
	docker tag $(USER)-jupyter $(DOCKERHUB_ACCOUNT)/jupyter
	# Build image for on k8s cluster with a GPU and push
	docker build -f gpu.Dockerfile -t $(USER)-jupyter-gpu .
	docker tag $(USER)-jupyter-gpu $(DOCKERHUB_ACCOUNT)/jupyter-gpu

push:
	# Push our containers to dockerhub for running in k8s
	docker push $(DOCKERHUB_ACCOUNT)/jupyter
	docker push $(DOCKERHUB_ACCOUNT)/jupyter-gpu

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
		-e DEBUG=True \
		-e USER=$(USER) \
		-e HOME=/tf \
		-e AWS_PROFILE="prp" \
		-e AWS_S3_ENDPOINT="https://s3.nautilus.optiputer.net" \
		-e S3_ENDPOINT="s3.nautilus.optiputer.net" \
		-p $(JUPYTER_PORT):8888 \
		-v `readlink -f ~`:/tf \
		-v `readlink -f ~/.empty`:/tf/.local \
		-v `readlink -f ~/data`:/tf/data \
		-v /public/groups/braingeneers:/public/groups/braingeneers \
		-v /public/groups/brcaexchange:/public/groups/brcaexchange \
		--shm-size=64G --memory=128G --cpus="16" --cpuset-cpus=1-16 \
		$(USER)-jupyter:latest jupyter notebook \
		--NotebookApp.certfile=/tf/jupyter/ssl/certs/ssl.cert.pem \
		--NotebookApp.keyfile=/tf/jupyter/ssl/private/ssl.key.pem \
		--ip=0.0.0.0 \
		--NotebookApp.password=$(JUPYTER_PASSWORD)

shell:
	# Shell into the jupyter notebook server
	docker exec -it $(USER)-jupyter /bin/bash

run-notebook:
	docker exec -it -e DEBUG=False $(USER)-jupyter \
		jupyter nbconvert --ExecutePreprocessor.timeout=None --to notebook \
		--execute $(NOTEBOOK) --output /tf/jobs/`date "+%Y%m%d-%H%M%S"`-$(notdir $(NOTEBOOK))

clean-jobs:
	# Delete k8s jobs and all PRP S3 jobs input and output
	kubectl get jobs -o custom-columns=:.metadata.name --namespace=braingeneers \
		| grep '^$(USER)*' | xargs kubectl delete jobs
	aws --profile prp --endpoint https://s3.nautilus.optiputer.net \
		s3 rm --recursive s3://braingeneers/$(USER)/jobs
	rm -rf jobs/

# Various ceremony to manually run on kubernettes, see job.py for
# a more elegant approach using jobs

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

shell-pod:
	# Open a shell on the pod
	kubectl exec -it $(USER)-pod /bin/bash

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
