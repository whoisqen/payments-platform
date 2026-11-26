import { createSign } from "node:crypto";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { SSMClient, PutParameterCommand } from "@aws-sdk/client-ssm";
import { AutoScalingClient, CompleteLifecycleActionCommand } from "@aws-sdk/client-auto-scaling";

const secrets = new SecretsManagerClient({});
const ssm = new SSMClient({});
const autoscaling = new AutoScalingClient({});
const pools = JSON.parse(process.env.POOLS);
const repository = process.env.REPOSITORY;

const b64url = (v) => Buffer.from(v).toString("base64url");

function appJwt(appId, privateKey) {
  const now = Math.floor(Date.now() / 1000);
  const body = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64url(JSON.stringify({ iat: now - 60, exp: now + 540, iss: String(appId) }))}`;
  return `${body}.${createSign("RSA-SHA256").update(body).sign(privateKey, "base64url")}`;
}

async function github(path, token, body) {
  const res = await fetch(`https://api.github.com${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${path} returned ${res.status}`);
  return res.json();
}

// Labels and repository come from Terraform, never from the instance, so a pull request cannot widen what its runner accepts.
async function issue(pool, instanceId) {
  const secret = JSON.parse((await secrets.send(new GetSecretValueCommand({ SecretId: pool.secret_id }))).SecretString);
  const installation = await github(`/app/installations/${secret.installation_id}/access_tokens`, appJwt(secret.app_id, secret.private_key), {
    repositories: [repository.split("/")[1]],
    permissions: { administration: "write" },
  });
  const jit = await github(`/repos/${repository}/actions/runners/generate-jitconfig`, installation.token, {
    name: instanceId,
    runner_group_id: Number(process.env.RUNNER_GROUP_ID),
    labels: pool.labels,
    work_folder: "_work",
  });
  await ssm.send(new PutParameterCommand({
    Name: `${pool.parameter_prefix}/${instanceId}`,
    Value: jit.encoded_jit_config,
    Type: "SecureString",
    KeyId: process.env.KMS_KEY_ID,
    Overwrite: false,
  }));
}

export const handler = async (event) => {
  const d = event.detail;
  const pool = pools[d.AutoScalingGroupName];
  if (!pool) throw new Error(`unknown group ${d.AutoScalingGroupName}`);
  let result = "ABANDON";
  try {
    await issue(pool, d.EC2InstanceId);
    result = "CONTINUE";
  } catch (err) {
    console.error(`no runner config for ${d.EC2InstanceId}: ${err.message}`);
  }
  // ABANDON terminates an instance that got no config, so the group never keeps a runner that cannot register.
  await autoscaling.send(new CompleteLifecycleActionCommand({
    AutoScalingGroupName: d.AutoScalingGroupName,
    LifecycleHookName: d.LifecycleHookName,
    LifecycleActionToken: d.LifecycleActionToken,
    InstanceId: d.EC2InstanceId,
    LifecycleActionResult: result,
  }));
};
