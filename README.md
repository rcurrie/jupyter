# A Jupyter Cloud Button

Tooling to run a secure Jupyter notebook server on your laptop or shared server and scale up by executing notebooks in a kubernetes job.

See the Makefile for various ceremony to build docker images and start a local notebooks server.

See job.py for details on automatically scaling up your notebook by running it in a kubernetes job and copying the executed notebook back to a local jobs/ folder.

# Running a Notebook on Kubernetes

Run test.ipynb in a kubernetes job, wait for it to complete and copy it back to ./jobs/:
```
python2 job.py -n namespace -w test.ipynb
```

Run test.ipynb but return immediately. Useful to run multiple versions in parallel:
```
python2 job.py -n namespace test.ipynb
```

Run test.ipynb and print output to the console:
```
python2 job.py -n namespace -l test.ipynb
```

Copy any complete jobs back to ./jobs/:
```
python2 job.py -n namespace
```

# Running a Jupyter Server

Build customer containers for CPU/Local and GPU and push to dockerhub:
```
make build
```

Generate certificates to run the Jupyter server encrypted:
```
make generate-ca generate-ssl
```

Run local Jupyter notebook server with password and local directory mapped in:
```
make jupyter
```

The first time you'll have to add the certificate to your browser

Run a notebook inside the running Jupyter notebook server container on the command line:
```
NOTEBOOK=path/from/home/overview.ipynb make run-notebook
```
Useful when you have a notebook that you want to run for a long time and still capture the output/images. If you try in a browser it may disconnect with the notebook running to completion but with all the output missing. DEBUG is set to False when running so you can slim down the notebook when in interactive and run the full data when on the command line.
