import json

import boto3


def handler(events, context):
    job = boto3.client("backup").describe_restore_job(RestoreJobId=events["RestoreJobId"])
    ok = events["Status"] == "COMPLETED"
    if ok and events["ValidatorArn"]:
        reply = boto3.client("lambda").invoke(
            FunctionName=events["ValidatorArn"],
            Payload=json.dumps({"restoreJobId": events["RestoreJobId"], "resourceType": events["ResourceType"]}),
        )
        ok = "FunctionError" not in reply
    done = job.get("CompletionDate") or job["CreationDate"]
    seconds = (done - job["CreationDate"]).total_seconds()
    dims = [{"Name": "Store", "Value": events["ResourceType"].lower()}]
    boto3.client("cloudwatch").put_metric_data(
        Namespace=events["Namespace"],
        MetricData=[
            {"MetricName": "RestoreDurationSeconds", "Dimensions": dims, "Value": seconds, "Unit": "Seconds"},
            {"MetricName": "RestoreTargetSeconds", "Dimensions": dims, "Value": float(events["TargetSeconds"]), "Unit": "Seconds"},
            {"MetricName": "RestoreSuccess", "Dimensions": dims, "Value": 1.0 if ok else 0.0, "Unit": "Count"},
        ],
    )
    return {"Seconds": seconds, "Success": ok}
