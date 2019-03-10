"""
Run a jupyter notebook in a kubernettes job

Notes:
    Requires python2.7 to work with PRP due to OID issues...

Requirements:
    pip2 install --pre --user --upgrade kubernetes
"""
import os
import time
import datetime
import argparse
import yaml
import kubernetes


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description="Run a Jupyter notebook in a Kubernetes cluster")
    parser.add_argument("notebook", nargs="?", help="Notebook to run")
    args = parser.parse_args()

    kubernetes.config.load_kube_config()
    api_client = kubernetes.client.ApiClient()
    batch_api = kubernetes.client.BatchV1Api(api_client)
    core_api = kubernetes.client.CoreV1Api(api_client)

    namespace = kubernetes.config.list_kube_config_contexts()[1]['context']['namespace']
    print("Using namespace {}".format(namespace))

    jobs = batch_api.list_namespaced_job(namespace)
    print("Current jobs", [item.metadata.name for item in jobs.items])

    if args.notebook:

        with open("jjob.yml") as f:
            body = yaml.load(f)

        body["metadata"]["name"] = "{}-{}".format(
            os.environ["USER"], datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
        body["metadata"]["labels"] = {"notebook": args.notebook}

        job = batch_api.create_namespaced_job(body=body, namespace=namespace)

    # Watch and stream the logs
    w = kubernetes.watch.Watch()
    for event in w.stream(core_api.list_namespaced_event, namespace=namespace):
        # print(event["raw_object"]["message"])
        # print(event["raw_object"]["reason"])
        # print(event["raw_object"]["involvedObject"]["name"])
        # print(event["raw_object"]["involvedObject"]["uid"])
        # print(event["raw_object"]["metadata"]["uid"])
        # print(event)
        # continue
        if (event["raw_object"]["reason"] == "Started"
                and job.metadata.name in event["raw_object"]["metadata"]["name"]):
            print("Started:")
            print(event["raw_object"]["message"])
            print(event["raw_object"]["reason"])
            print(event["raw_object"]["involvedObject"]["name"])
            print(event["raw_object"]["involvedObject"]["uid"])
            print(event["raw_object"]["metadata"]["uid"])
            print(event)

            names = [item.metadata.name
                     for item in core_api.list_namespaced_pod(namespace).items
                     if job.metadata.name in item.metadata.name]
            print(names)

            time.sleep(5)

            for line in core_api.read_namespaced_pod_log(
                    names[0], namespace, follow=True, _preload_content=False).stream():
                print(line)
