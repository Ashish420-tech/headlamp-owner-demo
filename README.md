# Headlamp Owner Demo – Secure HTTPS Dashboard for Amazon EKS

A Terraform-based project that deploys a secure, publicly accessible Headlamp dashboard for an existing Amazon EKS cluster.

The solution uses an AWS EC2 gateway, AWS Systems Manager, Kubernetes RBAC, a persistent `kubectl port-forward` service, Caddy reverse proxy, HTTPS, and authentication.

The goal is to let a project owner inspect Kubernetes workloads, nodes, namespaces, services, metrics, and Karpenter resources through a browser without exposing the Kubernetes API server directly to the public internet.

---

## 1. Project Overview

### What does this project do?

This project creates a dedicated EC2 gateway that securely connects to an existing EKS cluster and publishes the Headlamp dashboard over HTTPS.

A project owner can access the dashboard through a browser without keeping a laptop, WSL terminal, or local port-forward session running.

### Main features

- Public HTTPS access to Headlamp.
- Terraform-based AWS infrastructure provisioning.
- EC2 Ubuntu 24.04 gateway.
- AWS Systems Manager integration.
- Caddy reverse proxy.
- Automatic HTTPS certificate provisioning.
- HTTP Basic Authentication at the gateway.
- Kubernetes service-account authentication inside Headlamp.
- Read-only Kubernetes permissions for the dashboard viewer.
- Kubernetes metrics visibility.
- Karpenter custom resource visibility.
- Persistent port-forwarding through systemd.
- Existing EKS cluster reuse.

### Architecture

```text
                 PROJECT OWNER
                       |
                       |
                  Web Browser
                       |
                       | HTTPS :443
                       |
                       v
             +---------------------+
             |   Public EC2 EIP    |
             |   nip.io hostname   |
             +---------------------+
                       |
                       v
             +---------------------+
             |        Caddy        |
             | HTTPS + TLS         |
             | Basic Authentication|
             +---------------------+
                       |
                       | localhost:8080
                       v
             +---------------------+
             | systemd Service     |
             | kubectl port-forward|
             +---------------------+
                       |
                       | Kubernetes API
                       v
             +---------------------+
             | Existing Amazon EKS |
             |                     |
             | Headlamp Service    |
             | Headlamp Pod        |
             +---------------------+
                       |
                       v
             +---------------------+
             | Kubernetes RBAC     |
             | Read-only Viewer    |
             +---------------------+
```

### Technology stack

| Technology | Purpose |
|---|---|
| AWS EC2 | Public gateway server |
| Amazon EKS | Existing Kubernetes platform |
| Terraform | Infrastructure provisioning |
| Ubuntu 24.04 | Gateway operating system |
| AWS Systems Manager | EC2 administration |
| Caddy | HTTPS and reverse proxy |
| Headlamp | Kubernetes dashboard |
| Kubernetes RBAC | Viewer permissions |
| Metrics Server | Pod and node metrics |
| Karpenter | NodePool and NodeClaim visibility |
| systemd | Persistent port-forward service |
| nip.io | DNS hostname based on public IP |

---

## 2. Repository Structure

```text
headlamp-owner-demo/
│
├── main.tf
├── variables.tf
├── outputs.tf
├── versions.tf
├── .terraform.lock.hcl
├── .gitignore
│
├── terraform.tfvars.example
│
├── gateway.sh.tftpl
│
├── kubernetes-headlamp-rbac.yaml
├── headlamp-metrics-rbac.yaml
├── headlamp-crd-discovery-rbac.yaml
├── headlamp-storageclass-rbac.yaml
│
└── karpenter-arm64-smoke.yaml
```

### File descriptions

| File | Description |
|---|---|
| `main.tf` | Main AWS infrastructure configuration |
| `variables.tf` | Terraform input variables |
| `outputs.tf` | Infrastructure outputs |
| `versions.tf` | Terraform and provider requirements |
| `.terraform.lock.hcl` | Provider dependency lock file |
| `terraform.tfvars.example` | Example configuration |
| `gateway.sh.tftpl` | EC2 gateway bootstrap template |
| `kubernetes-headlamp-rbac.yaml` | Headlamp viewer RBAC configuration |
| `headlamp-metrics-rbac.yaml` | Metrics API permissions |
| `headlamp-crd-discovery-rbac.yaml` | CRD discovery permissions |
| `headlamp-storageclass-rbac.yaml` | StorageClass permissions |
| `karpenter-arm64-smoke.yaml` | ARM64 Karpenter smoke-test workload |

---

## 3. Prerequisites

Before deploying, prepare the following:

### Local workstation

- Linux, macOS, or WSL Ubuntu.
- AWS CLI v2.
- Terraform.
- kubectl.
- Git.
- AWS credentials with appropriate infrastructure permissions.
- Access to the existing EKS cluster.

Verify the tools:

```bash
aws --version
terraform version
kubectl version --client
git --version
```

### AWS requirements

You need:

1. An existing EKS cluster.
2. An existing VPC.
3. An existing subnet suitable for the gateway.
4. The appropriate EKS cluster security group ID.
5. An IAM configuration that permits the gateway to access the EKS cluster.
6. Permission to create the EC2 gateway, security group, IAM resources, and Elastic IP as defined by the Terraform configuration.

This repository is designed to reuse an existing EKS cluster. It does not require creating another cluster.

---

## 4. Configure AWS CLI

Check the currently configured AWS identity:

```bash
aws sts get-caller-identity
```

Configure AWS credentials if necessary:

```bash
aws configure
```

Select the AWS region:

```bash
aws configure set region ap-south-1
```

Verify:

```bash
aws configure get region
aws sts get-caller-identity
```

Use an IAM identity with the permissions needed by this project. Avoid hardcoding access keys in Terraform files.

---

## 5. Configure the Existing EKS Cluster

Set your cluster information:

```bash
export AWS_REGION="ap-south-1"
export CLUSTER_NAME="YOUR_EKS_CLUSTER_NAME"
```

Check the cluster:

```bash
aws eks describe-cluster \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME" \
  --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' \
  --output table
```

Configure kubectl:

```bash
aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$CLUSTER_NAME"
```

Verify connectivity:

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get namespaces
```

Check that Headlamp is already installed:

```bash
kubectl get pods -n headlamp
kubectl get svc -n headlamp
```

The Headlamp namespace and service must exist before the gateway's port-forward can work.

---

## 6. Configure Terraform

Clone the repository:

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/headlamp-owner-demo.git

cd headlamp-owner-demo
```

Initialize Terraform:

```bash
terraform init
```

Create your local configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit the configuration:

```bash
nano terraform.tfvars
```

Example:

```hcl
region       = "ap-south-1"
cluster_name = "YOUR_EKS_CLUSTER_NAME"

vpc_id                    = "vpc-YOUR_VPC_ID"
subnet_id                 = "subnet-YOUR_SUBNET_ID"
cluster_security_group_id = "sg-YOUR_SECURITY_GROUP_ID"

dashboard_username = "projectowner"
dashboard_password = "REPLACE_WITH_A_STRONG_UNIQUE_PASSWORD"
```

Use the actual resource IDs from your AWS account.

**Important:** Keep `terraform.tfvars` private. It must never be committed to GitHub.

The password should be unique and strong. Do not paste it into chat, logs, screenshots, or public documentation.

---

## 7. Validate Terraform Configuration

Format the Terraform files:

```bash
terraform fmt -recursive
```

Validate:

```bash
terraform validate
```

Review the execution plan:

```bash
terraform plan -out=headlamp-owner-demo.tfplan
```

Inspect the plan carefully.

Check especially:

- VPC and subnet selection.
- Security group rules.
- EC2 instance configuration.
- IAM roles and policies.
- Elastic IP allocation.
- EKS access configuration.
- Resource changes and destruction.

Do not proceed if Terraform proposes destroying or recreating an existing EKS cluster or unrelated infrastructure.

Apply:

```bash
terraform apply headlamp-owner-demo.tfplan
```

After successful deployment:

```bash
terraform output
```

The outputs provide the gateway information defined by this Terraform project.

---

## 8. Verify the EC2 Gateway

Find the created instance:

```bash
aws ec2 describe-instances \
  --region ap-south-1 \
  --filters "Name=tag:Name,Values=*Headlamp*" \
  --query 'Reservations[].Instances[].{ID:InstanceId,State:State.Name,IP:PublicIpAddress,PrivateIP:PrivateIpAddress}' \
  --output table
```

If the instance name differs, inspect the Terraform outputs or EC2 console.

Verify that the instance is running:

```bash
aws ec2 describe-instance-status \
  --region ap-south-1 \
  --instance-ids YOUR_INSTANCE_ID
```

Check Systems Manager connectivity:

```bash
aws ssm describe-instance-information \
  --region ap-south-1 \
  --output table
```

The EC2 instance should appear as online before attempting SSM administration.

---

## 9. Configure Kubernetes Permissions

The gateway needs permission to access the EKS cluster and forward traffic to Headlamp.

The project includes these Kubernetes permission files:

```text
kubernetes-headlamp-rbac.yaml
headlamp-metrics-rbac.yaml
headlamp-crd-discovery-rbac.yaml
headlamp-storageclass-rbac.yaml
```

Apply them using an authorized Kubernetes administrator identity:

```bash
kubectl apply -f kubernetes-headlamp-rbac.yaml

kubectl apply -f headlamp-metrics-rbac.yaml

kubectl apply -f headlamp-crd-discovery-rbac.yaml

kubectl apply -f headlamp-storageclass-rbac.yaml
```

Verify the resources:

```bash
kubectl get serviceaccount -n headlamp

kubectl get clusterrole | grep headlamp

kubectl get clusterrolebinding | grep headlamp
```

### Verify viewer permissions

```bash
SA="system:serviceaccount:headlamp:headlamp-viewer"

kubectl auth can-i list nodes \
  --as="$SA"

kubectl auth can-i list pods \
  --as="$SA" \
  --all-namespaces

kubectl auth can-i list namespaces \
  --as="$SA"

kubectl auth can-i list services \
  --as="$SA" \
  -n headlamp

kubectl auth can-i list nodepools.karpenter.sh \
  --as="$SA"
```

Check that the viewer cannot modify workloads:

```bash
kubectl auth can-i create pods \
  --as="$SA" \
  -n default

kubectl auth can-i delete pods \
  --as="$SA" \
  -n default
```

For a read-only viewer, the expected answer to the last two checks is:

```text
no
```

Review the actual RBAC manifests before deploying them into another environment. Permissions should be limited to the resources the owner needs to inspect.

---

## 10. Enable Kubernetes Metrics

Headlamp requires a working metrics API for node and pod CPU and memory information.

Check whether Metrics Server is installed:

```bash
kubectl get deployment metrics-server -n kube-system
```

Check the API:

```bash
kubectl get apiservice v1beta1.metrics.k8s.io
```

For an EKS version that supports the EKS-managed Metrics Server add-on, inspect available versions:

```bash
aws eks describe-addon-versions \
  --region ap-south-1 \
  --addon-name metrics-server
```

If the add-on is not installed, select a version compatible with your EKS cluster and install it:

```bash
aws eks create-addon \
  --region ap-south-1 \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name metrics-server \
  --addon-version YOUR_COMPATIBLE_ADDON_VERSION \
  --resolve-conflicts PRESERVE
```

Check add-on status:

```bash
aws eks describe-addon \
  --region ap-south-1 \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name metrics-server \
  --query 'addon.{Status:status,Issues:health.issues}' \
  --output json
```

Verify metrics:

```bash
kubectl top nodes
kubectl top pods -A
```

If metrics are unavailable, inspect the Metrics Server pods and APIService before troubleshooting Headlamp.

---

## 11. Configure Headlamp Access

The project uses two authentication layers:

**Layer 1 – Gateway authentication**

Caddy protects the public HTTPS endpoint with HTTP Basic Authentication.

**Layer 2 – Kubernetes authentication**

Headlamp uses a Kubernetes service-account bearer token for the viewer account.

Generate a fresh token:

```bash
kubectl create token headlamp-viewer \
  -n headlamp \
  --duration=8h
```

Copy the token securely to the authorized owner.

Do not commit the token or place it in the README.

The token is time-limited. Generate a new token when it expires.

---

## 12. Verify the Persistent Port Forward

The gateway uses a systemd service to keep the Headlamp connection running.

The expected port mapping is:

```text
EC2 localhost:8080 → Kubernetes Headlamp Service:80
```

Connect to the EC2 gateway through Systems Manager:

```bash
aws ssm start-session \
  --region ap-south-1 \
  --target YOUR_INSTANCE_ID
```

Inside the EC2 instance, check the service:

```bash
sudo systemctl status headlamp-tunnel
```

Check recent logs:

```bash
sudo journalctl \
  -u headlamp-tunnel \
  -n 100 \
  --no-pager
```

Follow logs:

```bash
sudo journalctl \
  -u headlamp-tunnel \
  -f
```

Check the local Headlamp endpoint:

```bash
curl -I http://127.0.0.1:8080
```

Expected result:

```text
HTTP/1.1 200 OK
```

If the service is stopped:

```bash
sudo systemctl restart headlamp-tunnel
```

Enable it at boot:

```bash
sudo systemctl enable headlamp-tunnel
```

---

## 13. Verify Caddy and HTTPS

Caddy provides the HTTPS endpoint and reverse proxy.

Check Caddy:

```bash
sudo systemctl status caddy
```

Validate the configuration:

```bash
sudo caddy validate \
  --config /etc/caddy/Caddyfile
```

Check the service logs:

```bash
sudo journalctl \
  -u caddy \
  -n 100 \
  --no-pager
```

Restart if needed:

```bash
sudo systemctl restart caddy
```

Check HTTPS:

```bash
curl -I https://YOUR_PUBLIC_HOSTNAME
```

An HTTP `401 Unauthorized` response is expected when Basic Authentication is enabled and no credentials are supplied.

Check certificate and TLS details:

```bash
curl -Iv https://YOUR_PUBLIC_HOSTNAME
```

Caddy should obtain and renew its TLS certificate automatically when its ACME validation requirements are satisfied.

---

## 14. Access Headlamp from a Browser

Open the HTTPS hostname shown in Terraform outputs.

Example hostname format:

```text
https://YOUR_PUBLIC_IP.nip.io
```

The login process is:

1. Open the HTTPS URL.
2. Enter the Caddy Basic Authentication username.
3. Enter the gateway password.
4. Open the Headlamp dashboard.
5. Select the bearer-token authentication option.
6. Paste the fresh `headlamp-viewer` token.
7. Connect to the Kubernetes cluster.

After successful login, the owner should be able to inspect the Kubernetes resources permitted by the RBAC configuration.

---

## 15. Validate the Dashboard

Check the following pages:

| Headlamp page | Expected result |
|---|---|
| Overview | Cluster overview and metrics |
| Nodes | Kubernetes node list |
| Pods | Pod status and namespaces |
| Namespaces | Namespace list |
| Services | Kubernetes services |
| Storage | Storage resources permitted by RBAC |
| Custom Resources | Available custom resource definitions |
| Karpenter resources | NodePools, NodeClaims, EC2NodeClasses where permitted |
| Ingresses | Existing ingress resources, if any |

The Ingresses page may be empty if the cluster does not have Ingress resources. This is not necessarily a failure.

### Kubernetes verification commands

```bash
kubectl get nodes -o wide

kubectl get pods -A

kubectl get services -A

kubectl get namespaces

kubectl get nodepools

kubectl get nodeclaims

kubectl get ec2nodeclasses

kubectl top nodes

kubectl top pods -A
```

Some commands require the Karpenter CRDs to be installed.

---

## 16. Karpenter ARM64 Smoke Test

This repository also contains:

```text
karpenter-arm64-smoke.yaml
```

It can be used to verify ARM64 Karpenter provisioning, provided the existing cluster has a compatible ARM64 NodePool.

Review the manifest:

```bash
cat karpenter-arm64-smoke.yaml
```

Apply it:

```bash
kubectl apply -f karpenter-arm64-smoke.yaml
```

Monitor the pod:

```bash
kubectl get pods -A -w
```

Inspect Karpenter resources:

```bash
kubectl get nodepools

kubectl get nodeclaims

kubectl get nodes -L kubernetes.io/arch,karpenter.sh/nodepool
```

Check the test pod:

```bash
kubectl describe pod arm64-provisioning-test \
  -n karpenter-smoke
```

After the pod is running, inspect the node architecture:

```bash
kubectl get pod arm64-provisioning-test \
  -n karpenter-smoke \
  -o wide
```

For an ARM64 container, the architecture should be:

```text
aarch64
```

Clean up the smoke-test pod when finished:

```bash
kubectl delete -f karpenter-arm64-smoke.yaml
```

Allow Karpenter to perform its configured consolidation. Do not manually delete NodeClaims or EC2 instances as a cleanup shortcut.

---

## 17. Troubleshooting Guide

### Problem 1 – Headlamp page is unavailable

Check the tunnel:

```bash
sudo systemctl status headlamp-tunnel

sudo journalctl \
  -u headlamp-tunnel \
  -n 100 \
  --no-pager
```

Check the service:

```bash
kubectl get svc headlamp -n headlamp

kubectl get pods -n headlamp
```

Check the local endpoint:

```bash
curl -I http://127.0.0.1:8080
```

### Problem 2 – HTTPS returns 502 Bad Gateway

A 502 usually indicates that Caddy cannot reach the local Headlamp endpoint.

Check:

```bash
curl -I http://127.0.0.1:8080

sudo systemctl status headlamp-tunnel

sudo systemctl status caddy
```

Restart the tunnel first:

```bash
sudo systemctl restart headlamp-tunnel
```

Then check Caddy:

```bash
sudo systemctl restart caddy
```

### Problem 3 – HTTPS returns 401 Unauthorized

This can be expected if Basic Authentication credentials were not supplied or were incorrect.

Verify the Caddy configuration and credentials through the EC2 SSM session.

Do not disable authentication to troubleshoot a public endpoint.

### Problem 4 – Headlamp displays Forbidden

This usually indicates missing Kubernetes RBAC permissions.

Check the viewer identity:

```bash
kubectl auth can-i list nodes \
  --as=system:serviceaccount:headlamp:headlamp-viewer
```

Check the bindings:

```bash
kubectl get clusterrolebinding | grep headlamp

kubectl get clusterrole | grep headlamp
```

Review and reapply the appropriate RBAC manifest if needed.

### Problem 5 – CPU and memory metrics are unavailable

Check:

```bash
kubectl get pods -n kube-system | grep metrics-server

kubectl get apiservice v1beta1.metrics.k8s.io

kubectl top nodes
```

Check the metrics RBAC manifest:

```bash
cat headlamp-metrics-rbac.yaml
```

### Problem 6 – Custom Resources are not visible

Check the CRD discovery permissions:

```bash
kubectl get clusterrole headlamp-viewer-crd-discovery

kubectl get crd
```

Verify that the Headlamp viewer can discover CRDs.

### Problem 7 – EC2 gateway is not reachable through SSM

Check the EC2 instance status:

```bash
aws ec2 describe-instances \
  --region ap-south-1 \
  --instance-ids YOUR_INSTANCE_ID
```

Check Systems Manager registration:

```bash
aws ssm describe-instance-information \
  --region ap-south-1 \
  --output table
```

Verify the EC2 IAM role, SSM Agent, network connectivity, and instance status.

### Problem 8 – Terraform reports missing variables

Verify the local configuration:

```bash
ls -l terraform.tfvars
```

Review required variables:

```bash
cat variables.tf
```

Never solve missing-variable errors by hardcoding passwords or credentials in Terraform source files.

---

## 18. Security Recommendations

This is a public dashboard gateway. Protect it carefully.

1. Use a strong, unique Caddy Basic Authentication password.
2. Rotate any password or hash that has been exposed.
3. Use a short-lived Kubernetes bearer token.
4. Do not publish bearer tokens, credentials, private keys, Terraform state, or real `.tfvars` files.
5. Restrict Kubernetes viewer permissions to read-only access.
6. Limit EC2 inbound access to the required HTTPS port.
7. Keep SSH closed unless explicitly needed.
8. Use Systems Manager for administrative access.
9. Keep Terraform state in a secure location.
10. Review IAM permissions and security group rules regularly.
11. Monitor Caddy and systemd logs.
12. Use a dedicated IAM role with least privilege for the gateway.

### Files that must never be committed

```text
terraform.tfvars
terraform.tfstate
terraform.tfstate.*
*.tfplan
.env
*.pem
*.key
credentials
kubeconfig
```

---

## 19. Terraform Management Commands

From the project root:

```bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
terraform output
```

Refresh the plan before applying infrastructure changes.

If the gateway is no longer required, inspect the destruction plan carefully:

```bash
terraform plan -destroy
```

Only if you intentionally want to remove the resources managed by this Terraform state:

```bash
terraform destroy
```

**Warning:** Review the destroy plan before confirming. Do not destroy the existing EKS cluster or shared networking resources.

---

## 20. GitHub Contribution and Deployment

Clone:

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/headlamp-owner-demo.git

cd headlamp-owner-demo
```

Update:

```bash
git status
git add .
git status
```

Review staged files before committing.

Commit:

```bash
git commit -m "Add secure Headlamp owner dashboard deployment"
```

Push:

```bash
git push -u origin main
```

Never commit Terraform state, passwords, bearer tokens, or AWS credentials.

---

## 21. Expected Final Result

After a successful deployment:

- An EC2 gateway is running in the selected VPC and subnet.
- The gateway can connect to the existing EKS cluster.
- Headlamp is available through the local persistent port-forward.
- Caddy publishes the dashboard over HTTPS.
- Basic Authentication protects the public endpoint.
- Headlamp authenticates using a Kubernetes viewer token.
- The viewer can inspect authorized Kubernetes resources.
- Metrics are visible when Metrics Server and its RBAC are correctly configured.
- Karpenter resources are visible when the relevant CRDs and RBAC permissions are available.

---

## 22. Project Learning Outcomes

This project demonstrates practical experience with:

- Terraform infrastructure as code.
- AWS EC2 and Elastic IP.
- AWS IAM and EKS access configuration.
- Systems Manager administration.
- Kubernetes service accounts and RBAC.
- Kubernetes API access.
- Persistent Linux systemd services.
- Reverse proxy architecture.
- HTTPS and TLS certificate management.
- Secure dashboard publication.
- Kubernetes observability.
- Karpenter resource inspection.
- AWS infrastructure troubleshooting.

## 23. Important Project Scope

This repository deploys the Headlamp owner-access gateway and its supporting configuration for an existing EKS environment.

It does not independently create:

- An Amazon EKS cluster.
- A complete VPC.
- A complete Karpenter installation.
- The Headlamp application itself, if it is not already installed.

Those components must already exist or be installed separately.

---

**Project:** Headlamp Owner Demo  
**Cloud:** AWS  
**Kubernetes:** Amazon EKS  
**Infrastructure as Code:** Terraform  
**Dashboard:** Headlamp  
**Security:** HTTPS, Basic Authentication, Kubernetes RBAC  
**Gateway:** Ubuntu EC2 + Caddy + systemd

