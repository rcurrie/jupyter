"""
Run a jupyter notebook in a kubernettes job and copy back to ~/jobs

Example:
python3 job.py -n braingeneers -b braingeneers -w -l ~/path/to/notebook.ipynb

Details
- Copy the notebook to S3
- Launch a k8s job that runs the notebook via nbconvert sending logging back to the local console
- Copy the executed notebook back to S3
- Copy the executed notebook from S3 to ~/jobs with a timestamp

Notes:
    Notebooks are time stamped so you can run multiple versions

Requirements:
    pip3 install --user --upgrade kubernetes>=10.0.0 boto3
"""
import sys
import os
import datetime
import time
import argparse
import yaml
import boto3
import kubernetes


# kubernettes python seems to randomly complain...
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def sync(bucket, jobs_path):
    """ Sync the output of any jobs to the jobs folder and delete from S3 """
    for obj in bucket.objects.filter(Prefix="{}/jobs/out".format(os.environ["USER"])):
        if not os.path.exists(("{}/{}".format(jobs_path, os.path.basename(obj.key)))):
            print("Downloading {}".format(obj.key))
            bucket.Object(obj.key).download_file("{}/{}".format(
                jobs_path, os.path.basename(obj.key)))
        print("Deleting {}".format(obj.key))
        bucket.delete_objects(Delete={'Objects': [{'Key': obj.key}]})


def wait(name, batch_api, namespace):
    """ Wait for the named job to complete. """
    w = kubernetes.watch.Watch()
    for event in w.stream(batch_api.list_namespaced_job, namespace=namespace):
        if ("completionTime" in event["raw_object"]["status"] and
                name in event["raw_object"]["metadata"]["name"]):
            print("{} completed".format(job.metadata.name))
            return


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description="Run a Jupyter notebook in a Kubernetes cluster")
    parser.add_argument("notebook", nargs="?", help="Notebook to run")
    parser.add_argument("-n", "--namespace", required=True,
                        help="Kubernetes namespace to run jobs")
    parser.add_argument("-b", "--bucket", required=True,
                        help="S3 bucket to store notebooks")
    parser.add_argument("-w", "--wait", action="store_true",
                        help="Wait for job to complete")
    parser.add_argument("-l", "--log", action="store_true",
                        help="Log output of job")
    args = parser.parse_args()

    # Make jobs directory in the users home directory
    jobs_path = os.path.expanduser("~/jobs")
    if not os.path.exists(jobs_path):
        os.makedirs(jobs_path)

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
        "s3", endpoint_url="https://s3.nautilus.optiputer.net").Bucket(args.bucket)

    # If a notebook is specified copy to S3 and start a job
    if args.notebook:
        assert args.notebook.endswith(".ipynb")

        notebook_path = os.path.abspath(args.notebook)
        notebook_name = os.path.basename(args.notebook)

        in_path = "{}/jobs/in/{}-{}".format(os.environ["USER"], timestamp, notebook_name)
        out_path = "{}/jobs/out/{}-{}".format(os.environ["USER"], timestamp, notebook_name)
        bucket.Object(in_path).upload_file(notebook_path, ExtraArgs={"ACL": "public-read"})

        # Load job template and fill in any environment variables
        # REMIND: Bake into this file so we're self sufficient? Or Dockerize?
        with open(os.path.join(os.path.dirname(__file__), "job.yml")) as f:
            body = yaml.load(os.path.expandvars(f.read()))

        body["metadata"]["name"] = "{}-{}-{}".format(os.environ["USER"], timestamp, notebook_name)

        body["metadata"]["labels"] = {
            "user": os.environ["USER"],
            "timestamp": timestamp,
            "notebook": notebook_name}

        # Fill in script to copy notebook down, run, and copy back
        body["spec"]["template"]["spec"]["containers"][0]["args"] = ["""
          echo 'Copying notebook to pod...' &&
          aws --endpoint http://rook-ceph-rgw-rooks3.rook s3 cp s3://{4}/{1} {0} &&
          md5sum {0} &&
          echo 'Running notebook...' &&
          jupyter nbconvert --ExecutePreprocessor.timeout=None --to notebook \
                  --execute {0} --output {0} &&
          md5sum {0} &&
          echo 'Copying notebook back to S3...' &&
          aws --endpoint http://rook-ceph-rgw-rooks3.rook s3 cp {0} s3://{4}/{2} &&
          echo 'Deleting input notebook from S3...' &&
          aws --endpoint http://rook-ceph-rgw-rooks3.rook s3 rm s3://{4}/{1} &&
          echo 'Finished.'
        """.format(notebook_name, in_path, out_path, os.environ["USER"], args.namespace)]

        # Create and start the job
        job = batch_api.create_namespaced_job(body=body, namespace=namespace)
        print("Created job")

        # Log output
        if args.log:
            w = kubernetes.watch.Watch()
            try:
                for event in w.stream(core_api.list_namespaced_event, namespace=namespace):
                    if (event["raw_object"]["reason"] == "Started"
                            and job.metadata.name in event["raw_object"]["metadata"]["name"]):
                        names = [item.metadata.name
                                 for item in core_api.list_namespaced_pod(namespace).items
                                 if job.metadata.name in item.metadata.name]
                        print("Started as {} on {}".format(
                            event["raw_object"]["source"]["host"], names[0]))

                        # If we try and log immediately the job will not have started enough...
                        time.sleep(5)

                        for line in core_api.read_namespaced_pod_log(
                                names[0], namespace, follow=True, _preload_content=False).stream():
                            print(line)
            except KeyboardInterrupt:
                print("Quitting")

        # Wait until its finished
        elif args.wait:
            wait(job.metadata.name, batch_api, namespace)

    # Copy any output back and cleanup
    print("Syncing output...")
    sync(bucket, jobs_path)
    sys.exit()
