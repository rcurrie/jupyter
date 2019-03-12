"""
Run a jupyter notebook in a kubernettes job

Notes:
    Requires python2.7 to work with PRP due to OID issues:
    See https://github.com/kubernetes-client/python/issues/525

Requirements:
    pip2 install --pre --user --upgrade kubernetes
"""
import sys
import os
import datetime
import argparse
import yaml
import boto3
import kubernetes


def sync(bucket):
    """ Sync all the output of any jobs to the local jobs folder """
    for obj in bucket.objects.filter(Prefix="{}/jobs/out".format(os.environ["USER"])):
        if not os.path.exists("jobs/{}".format(os.path.basename(obj.key))):
            print("Downloading {}".format(obj.key))
            bucket.Object(obj.key).download_file("jobs/{}".format(os.path.basename(obj.key)))
        print("Deleting {}".format(obj.key))
        bucket.delete_objects(Delete={'Objects': [{'Key': obj.key}]})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description="Run a Jupyter notebook in a Kubernetes cluster")
    parser.add_argument("notebook", nargs="?", help="Notebook to run")
    parser.add_argument("-w", "--wait", action="store_true",
                        help="Wait for job to complete")
    args = parser.parse_args()

    # Make local jobs directory for output
    if not os.path.exists("jobs"):
        os.makedirs("jobs")

    # Common timestamp to use for job name and files
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

    # Connect to kubernetes
    kubernetes.config.load_kube_config()
    api_client = kubernetes.client.ApiClient()
    batch_api = kubernetes.client.BatchV1Api(api_client)
    core_api = kubernetes.client.CoreV1Api(api_client)
    namespace = kubernetes.config.list_kube_config_contexts()[1]['context']['namespace']
    print("Using namespace {}".format(namespace))

    # Connect to S3
    session = boto3.session.Session(profile_name="prp")
    bucket = session.resource(
        "s3", endpoint_url="https://s3.nautilus.optiputer.net").Bucket("braingeneers")

    # # Show a list of currently running jobs
    # jobs = batch_api.list_namespaced_job(namespace)
    # print("Current jobs", [item.metadata.name for item in jobs.items])

    if args.notebook:
        assert args.notebook.endswith(".ipynb")

        in_path = "{}/jobs/in/{}-{}".format(os.environ["USER"], timestamp, args.notebook)
        out_path = "{}/jobs/out/{}-{}".format(os.environ["USER"], timestamp, args.notebook)
        bucket.Object(in_path).upload_file(args.notebook, ExtraArgs={"ACL": "public-read"})

        # Load job template and fill in any environment variables
        with open("job.yml") as f:
            body = yaml.load(os.path.expandvars(f.read()))

        body["metadata"]["name"] = "{}-{}-{}".format(os.environ["USER"], timestamp, args.notebook)

        body["metadata"]["labels"] = {
            "user": os.environ["USER"],
            "timestamp": timestamp,
            "notebook": args.notebook}

        body["spec"]["template"]["spec"]["containers"][0]["args"] = ["""
          echo 'Copying notebook to pod...' &&
          aws --endpoint http://rook-ceph-rgw-rooks3.rook s3 cp s3://braingeneers/{1} {0} &&
          md5sum {0} &&
          echo 'Running notebook...' &&
          jupyter nbconvert --ExecutePreprocessor.timeout=None --to notebook \
                  --execute {0} --output {0} &&
          md5sum {0} &&
          echo 'Copying notebook back to S3...' &&
          aws --endpoint http://rook-ceph-rgw-rooks3.rook s3 cp {0} s3://braingeneers/{2} &&
          echo 'Deleting input notebook from S3...' &&
          aws --endpoint http://rook-ceph-rgw-rooks3.rook s3 rm s3://braingeneers/{1} &&
          echo 'Finished.'
        """.format(args.notebook, in_path, out_path, os.environ["USER"])]

        # pprint.pprint(body)
        # sys.exit()

        # Create and start the job
        job = batch_api.create_namespaced_job(body=body, namespace=namespace)
        print("Started job {}".format(job.metadata.name))

        # Wait until its finished
        if args.wait:
            w = kubernetes.watch.Watch()
            for event in w.stream(batch_api.list_namespaced_job, namespace=namespace):
                if ("completionTime" in event["raw_object"]["status"] and
                        job.metadata.name in event["raw_object"]["metadata"]["name"]):
                    print("{} completed".format(job.metadata.name))
                    bucket.Object(out_path).download_file(
                        "jobs/{}-{}".format(timestamp, args.notebook))
                    break

    # Copy any output back and cleanup
    print("Syncing output...")
    sync(bucket)
    sys.exit()

    # for event in w.stream(core_api.list_namespaced_event, namespace=namespace):
    #     print(event["raw_object"]["message"])
    #     print(event["raw_object"]["reason"])
    #     print(event["raw_object"]["involvedObject"]["name"])
    #     print(event["raw_object"]["involvedObject"]["uid"])
    #     print(event["raw_object"]["metadata"]["uid"])
    #     print(event)
    #     continue
    #     if (event["raw_object"]["reason"] == "Started"
    #             and job.metadata.name in event["raw_object"]["metadata"]["name"]):
    #         print("Started:")
    #         print(event["raw_object"]["message"])
    #         print(event["raw_object"]["reason"])
    #         print(event["raw_object"]["involvedObject"]["name"])
    #         print(event["raw_object"]["involvedObject"]["uid"])
    #         print(event["raw_object"]["metadata"]["uid"])
    #         print(event)

    #         names = [item.metadata.name
    #                  for item in core_api.list_namespaced_pod(namespace).items
    #                  if job.metadata.name in item.metadata.name]
    #         print(names)

    #         time.sleep(5)

    #         for line in core_api.read_namespaced_pod_log(
    #                 names[0], namespace, follow=True, _preload_content=False).stream():
    #             print(line)
