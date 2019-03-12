# A Jupyter Cloud Button

Tooling to run a secure Jupyter notebook server on your laptop or shared server and scale up by running executing notebooks in a kubernetes job.

See the Makefile for various ceremony to build docker images and start a local notebooks server.

See job.py for details on automatically scaling up your notebook by running it in a kubernetes job and copying the executed notebook back to a local jobs/ folder.
