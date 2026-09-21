# VulnTrack

A vulnerability and asset tracking web application built as a classic Java
3-tier stack — Jakarta EE on WildFly (JBoss), PostgreSQL, and a Dockerized
build/deploy pipeline. Built as a portfolio project to demonstrate full-stack
Java development, application-server administration, infrastructure as
code, and applied security in one connected system — and then deliberately
re-architected a second time onto Kubernetes with a real service mesh, to
demonstrate both approaches to running the same application in production.

![VulnTrack, live on its own domain over HTTPS](docs/screenshots/p5-25-polished-frontend-live-HERO.png)
*The findings dashboard, served from `aws.vulntrack.app` — real domain,
real Let's Encrypt certificate, running on an EKS cluster behind an Istio
service mesh with mutual TLS between pods.*

---

## Two architectures, one application

This project was deliberately built **twice**, on two different AWS
compute platforms, to demonstrate range rather than pick one and stop:

| | Phase 4 — ECS/Fargate | Phase 5 — EKS/Kubernetes |
|---|---|---|
| Compute | ECS Fargate (serverless containers) | EKS managed node group (real Kubernetes) |
| Ingress | ALB via Terraform | ALB via Kubernetes Ingress + Istio Gateway |
| DNS | Manual Route53 record | ExternalDNS, fully automated |
| TLS | ACM | Let's Encrypt (cert-manager), bridged into ACM |
| Service-to-service security | N/A (single service) | Istio service mesh, STRICT mutual TLS |
| Terraform | [`terraform-ecs/`](terraform-ecs/) | [`terraform-eks/`](terraform-eks/) |

Both are real, working, documented builds. Only one runs at a time (cost
reasons — see [Infrastructure as code](#infrastructure-as-code)), but the
code for both is preserved in this repo.

---

## Table of contents

- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Building it: from a failed archetype to a working REST API](#building-it-from-a-failed-archetype-to-a-working-rest-api)
- [Data model](#data-model)
- [API reference](#api-reference)
- [Authentication & authorization](#authentication--authorization)
- [Infrastructure as code](#infrastructure-as-code)
- [Phase 5: Kubernetes, a service mesh, and real TLS automation](#phase-5-kubernetes-a-service-mesh-and-real-tls-automation)
- [Phase 6: Proving the rebuild](#phase-6-proving-the-rebuild)
- [CI/CD pipeline](#cicd-pipeline)
- [Local development setup](#local-development-setup)
- [Troubleshooting log & lessons learned](#troubleshooting-log--lessons-learned)
- [Roadmap](#roadmap)

---

## Architecture

Classic 3-tier design at the application level, regardless of which
compute platform it's running on:

- **Presentation tier**: a lightweight static frontend (vanilla HTML/JS,
  no build step) plus a REST API, both served from the same WildFly
  deployment
- **Application tier**: Jakarta EE (JAX-RS + CDI) on WildFly, containerized
  via a custom Docker image
- **Data tier**: PostgreSQL, with a hand-installed WildFly datasource
  module rather than the default H2 example

**Phase 4 (ECS):**
```
 Browser ──> ALB ──> WildFly on ECS Fargate ──> PostgreSQL (RDS)
```

**Phase 5 (EKS):**
```
 Browser ──> Route53 (ExternalDNS) ──> ALB (WAF attached) ──> Istio Ingress Gateway
              ──mTLS──> WildFly pod + Envoy sidecar ──> PostgreSQL (RDS)
```

Locally, both phases run identically via Docker Compose — the app itself
doesn't know or care which cloud architecture it's deployed on, since all
environment-specific config (datasource host, JWT key) is injected at
runtime, not baked into the image.

See [`docs/diagrams/vulntrack-er-diagram.md`](docs/diagrams/vulntrack-er-diagram.md)
for the full entity-relationship diagram (renders automatically on GitHub).

---

## Tech stack

| Layer | Technology |
|---|---|
| Application server | WildFly 31 (JBoss) |
| Language / runtime | Java 17 (Eclipse Temurin) |
| Web framework | Jakarta EE 10 (JAX-RS, CDI) |
| ORM | Hibernate 6 / Jakarta Persistence |
| Database | PostgreSQL 16 |
| Auth | JWT (jjwt) + bcrypt (jBCrypt) |
| Frontend | Vanilla HTML/CSS/JS, no framework or build step |
| Build | Maven |
| Containerization | Docker, Docker Compose |
| Compute (Phase 4) | ECS Fargate |
| Compute (Phase 5) | EKS (Kubernetes), managed node group |
| Service mesh (Phase 5) | Istio — Ingress Gateway, sidecar injection, STRICT mTLS |
| DNS (Phase 5) | Route53 + ExternalDNS (automated) |
| TLS (Phase 5) | Let's Encrypt via cert-manager, bridged into ACM |
| WAF | AWS WAFv2 — managed rule groups + rate limiting |
| Infrastructure | Terraform (two independent root modules) |
| CI/CD | GitHub Actions, OIDC-authenticated (no stored AWS credentials) |

---

## Building it: from a failed archetype to a working REST API

The Maven archetype plugin failed outright on the very first command, so
the project was scaffolded by hand instead — writing `pom.xml` and the
folder structure directly rather than relying on generated templates.

![pom.xml validating successfully](docs/screenshots/03-pom-xml-build-success.png)
*The first clean `mvn validate` after hand-writing the Maven configuration*

That led to the first real milestone: WildFly running in Docker, serving a
REST endpoint end to end.

![WildFly starting in Docker for the first time](docs/screenshots/05-wildfly-docker-first-deploy.png)

![First successful ping through the whole stack](docs/screenshots/04-first-ping-alive-local.png)
*Maven → WAR → WildFly → REST, working end to end for the first time*

---

## Data model

Four core entities: `Asset`, `Vulnerability`, `Finding` (the join entity
linking a vulnerability to an asset with a status and remediation
deadline), and `AppUser`.

PostgreSQL runs as its own container/RDS instance with a **hand-installed
JDBC driver module** — WildFly doesn't ship one — configured via a CLI
script that runs during the Docker image build:

![The datasource CLI script](docs/screenshots/06b-datasource-cli-content.png)
*Registers the PostgreSQL driver and creates the `VulnTrackDS` datasource,
using `${env.VAR:default}` expressions so the same image works unchanged
across local Docker Compose, ECS, and EKS*

![Both datasources bound successfully](docs/screenshots/06c-datasources-bound-exampleds-vulntrackds.png)
*WildFly's default `ExampleDS` alongside the custom `VulnTrackDS`*

![All four tables created](docs/screenshots/06e-schema-dt-tables.png)
*Hibernate mapped all four JPA entities to real Postgres tables*

![A joined query proving the relationships work](docs/screenshots/06f-joined-query-relational-proof.png)
*A single SQL join across all four tables — the clearest proof the
relational model is correct, not just that the tables exist*

---

## API reference

Base path: `/vulntrack/api`

| Method | Endpoint | Auth required | Notes |
|---|---|---|---|
| POST | `/auth/register` | No | Creates a user (bcrypt-hashed password) |
| POST | `/auth/login` | No | Returns a signed JWT (1-hour expiry) |
| GET | `/assets` | Yes | List all assets |
| GET | `/assets/{id}` | Yes | Get one asset |
| POST | `/assets` | Yes | Create an asset |
| PUT | `/assets/{id}` | Yes | Update an asset |
| DELETE | `/assets/{id}` | Yes (**ADMIN only**) | Delete an asset |
| GET / POST / PUT / DELETE | `/vulnerabilities`, `/vulnerabilities/{id}` | Yes | Same CRUD pattern |
| GET / POST / PUT / DELETE | `/users`, `/users/{id}` | Yes | Same CRUD pattern |
| GET / POST / PUT / DELETE | `/findings`, `/findings/{id}` | Yes | Accepts `assetId` / `vulnerabilityId` / `assignedUserId` in the request body; the server resolves the actual entities |

![First successful write through the API](docs/screenshots/06g-crud-post-asset-201.png)
*`201 Created` confirming the full write path — REST → JPA → Postgres*

---

## Authentication & authorization

- Passwords are hashed with bcrypt before storage — never stored plain
- `POST /auth/login` returns a JWT signed with HS384, containing the
  username (`sub`) and role (`role`) claims
- A `ContainerRequestFilter` (`AuthFilter`) validates the
  `Authorization: Bearer <token>` header on every request except
  `/auth/*` and the health-check endpoint `/ping`
- Role checks are enforced per-endpoint using a `@RequestScoped` CDI bean
  (`RequestUserContext`) shared between the filter and the resource
  classes — a CDI-proxied JAX-RS resource can't reliably inject
  `ContainerRequestContext` directly, so this bean bridges the filter and
  the resource cleanly (see [Troubleshooting log](#troubleshooting-log--lessons-learned))
- Example: `DELETE /assets/{id}` is restricted to `ADMIN`; `ANALYST` users
  get `403 Forbidden`

Verified against a **live AWS deployment**, not just locally:

![Login against the live AWS API](docs/screenshots/22-aws-live-login-200-with-token.png)
*A real JWT issued by the production deployment*

![Protected endpoint responding correctly](docs/screenshots/23-aws-live-protected-endpoint-200.png)
*The same token used to call a protected endpoint — `200 OK`, proving the
full auth chain works against RDS in the real environment*

> **Note on the JWT signing key**: `JwtUtil.java` reads `JWT_SIGNING_KEY`
> from the environment (injected from Secrets Manager in both the ECS and
> EKS deployments), falling back to a clearly-commented dev-only value
> when that variable isn't set — so local Docker Compose runs need no
> configuration at all.

---

## Infrastructure as code

The AWS environment — VPC, security groups, RDS, compute, load balancer,
Secrets Manager — is fully defined in Terraform, in **two independent
root modules**:

- [`terraform-ecs/`](terraform-ecs/) — the original Phase 4 build: ECS
  Fargate, ALB with ACM, Secrets Manager
- [`terraform-eks/`](terraform-eks/) — the Phase 5 rebuild: EKS, IRSA
  roles for every mesh/DNS/cert component, RDS, WAF, EKS access entries

![Terraform plan before applying](docs/screenshots/18-terraform-plan-35-to-add.png)
*Reviewing exactly what will be created before committing to it*

![Infrastructure fully provisioned](docs/screenshots/21-terraform-apply-complete-HERO.png)
*`Apply complete!` — real AWS infrastructure, built entirely from code*

Neither environment is left running continuously — RDS, NAT gateways, and
EKS's control plane all carry real hourly cost. `terraform destroy` tears
everything down cleanly; `terraform apply` rebuilds it — and
[Phase 6](#phase-6-proving-the-rebuild) documents exactly what that took
in practice. State for `terraform-eks/` lives in a versioned S3 bucket
with native S3 locking. IAM
identities, the ECR repository, and the GitHub OIDC provider are shared
infrastructure outside either Terraform module and persist across
destroy/apply cycles for both.

---

## Phase 5: Kubernetes, a service mesh, and real TLS automation

Phase 4 proved the application worked well on serverless containers.
Phase 5 asks a different question: what does the same application look
like on a real, self-managed Kubernetes cluster, with a service mesh
providing pod-to-pod encryption and a fully automated DNS/TLS chain?

### Reorganizing for two architectures

The existing ECS Terraform config was moved into its own folder before
any EKS work began, so neither build could interfere with the other:

![Reorganizing into terraform-ecs/](docs/screenshots/p5-01-reorg-terraform-ecs-folder.png)

### Domain and DNS delegation

`vulntrack.app` was registered through Cloudflare — and Cloudflare's
registrar terms **contractually require using Cloudflare's own
nameservers**, which blocks the planned Route53 integration outright (not
a missing feature — an explicit registrar policy). Rather than wait out
the mandatory 60-day ICANN transfer lock, DNS was delegated one level
down: a Route53 hosted zone was created for `aws.vulntrack.app`
specifically, and Cloudflare was given an `NS` record pointing that one
subdomain at Route53. Everything under `aws.vulntrack.app` is fully
Route53-managed; the root domain stays with Cloudflare.

![Cloudflare NS delegation records](docs/screenshots/p5-02-cloudflare-ns-delegation-records.png)
*Four Route53 nameservers registered as an NS record for the `aws`
subdomain — delegation confirmed working within minutes*

### The EKS cluster

A dedicated VPC, an EKS control plane, and a managed EC2 node group —
deliberately **not** Fargate profiles, since Istio's sidecar networking
requires `iptables` manipulation that Fargate doesn't support.

![EKS Terraform plan](docs/screenshots/p5-03-eks-terraform-init-plan.png)

![EKS cluster and node group created](docs/screenshots/p5-04-eks-nodegroup-apply-complete.png)

![kubectl connected, nodes Ready](docs/screenshots/p5-05-kubectl-connected-nodes-ready.png)

The AWS Load Balancer Controller was installed via Helm shortly after —
this is what lets a Kubernetes `Ingress` resource provision a real ALB:

![Load Balancer Controller healthy](docs/screenshots/p5-06-load-balancer-controller-healthy.png)

### The pod-density ceiling (and the proper fix)

Once cert-manager and the Istio control plane were added, pods started
getting stuck `Pending` even with spare CPU/memory showing on every node:

![FailedScheduling: insufficient memory, too many pods](docs/screenshots/p5-07-pod-density-failedscheduling.png)

The real cause: `t3.micro`'s network interfaces can only hand out **4 pod
IPs per node**, a hard ceiling completely unrelated to CPU or RAM. A quick
node-count increase unblocked things temporarily —

![Four nodes, pods scheduled](docs/screenshots/p5-08-four-nodes-pods-scheduled.png)

— but with Istio about to inject a sidecar into every pod (roughly
doubling pod count), that was only ever a stopgap. The actual fix: enable
**VPC CNI prefix delegation** and a custom node-group launch template
overriding `kubelet`'s `maxPods`, raising per-node capacity from 4 to 30:

![list-nodegroups + PODS:30 confirmed](docs/screenshots/p5-13-prefix-delegation-fix-pods-30.png)
*Three independent sources — Terraform state, the AWS API, and
`kubectl` itself — all agreeing the fix genuinely worked*

Getting the fix in required two IAM permissions no prior phase had ever
needed (`ec2:CreateLaunchTemplate`, and separately `ec2:RunInstances` —
EKS validates the *calling user's* launch-template permissions before
delegating the actual launch to its own service role) — see the
[Troubleshooting log](#troubleshooting-log--lessons-learned) for the full
diagnostic path.

### Ingress, TLS, and WAF

A Kubernetes `Ingress` resource triggers the Load Balancer Controller to
provision a real ALB:

![Ingress created, ALB address assigned](docs/screenshots/p5-11-ingress-alb-created.png)

![First successful request through the new ALB](docs/screenshots/p5-12-curl-alb-vulntrack-alive.png)

**TLS**: ALB's HTTPS listener only accepts ACM (or IAM-uploaded)
certificates natively — it has no way to reference a `cert-manager`
Secret directly. So the real certificate is issued by **Let's Encrypt**
via `cert-manager`, using a DNS-01 challenge solved automatically through
Route53 (an IRSA role scoped to exactly the `aws.vulntrack.app` hosted
zone, nothing else):

![cert-manager fully healthy](docs/screenshots/p5-14-cert-manager-healthy.png)

![ClusterIssuer registered with Let's Encrypt](docs/screenshots/p5-15-clusterissuer-ready-acme-registered.png)

![Certificate issued](docs/screenshots/p5-16-certificate-issued-letsencrypt.png)
*A real, valid certificate — issued, not self-signed, with normal 90-day
Let's Encrypt expiry and cert-manager auto-renewal*

That certificate is then **manually bridged into ACM** — extracting the
cert/key from the Kubernetes Secret cert-manager creates, splitting the
leaf certificate from its intermediate chain (Let's Encrypt returns them
concatenated; ACM's API wants them separate), and importing the result:

![ACM import succeeds](docs/screenshots/p5-17-acm-import-certificate-success.png)

> This bridge is a **manual, non-auto-renewing step** — a known,
> documented tradeoff of choosing Let's Encrypt specifically to
> demonstrate `cert-manager` skills, rather than just using ACM's own
> (free, auto-renewing) certificates directly. A production setup would
> automate the re-import on every 90-day renewal.

**DNS**: rather than a static Terraform record (which would go stale the
moment the ALB is recreated), **ExternalDNS** watches the Ingress and
manages the Route53 record automatically:

![Route53 alias records, ExternalDNS-managed](docs/screenshots/p5-18-route53-alias-records-externaldns.png)

**WAF**: an AWS WAFv2 Web ACL — three AWS-managed rule groups (common
exploits, known bad inputs, and SQL injection specifically, a fitting
choice for a vulnerability tracker) plus IP-based rate limiting — attached
directly to the ALB (originally through a Terraform association; moved to
an Ingress annotation in [Phase 6](#phase-6-proving-the-rebuild)):

![WAF Web ACL confirmed attached](docs/screenshots/p5-20-waf-webacl-get-for-resource.png)

All of it working together, live, over real HTTPS, on the actual domain:

![The full chain working: real domain, real cert](docs/screenshots/p5-19-live-https-domain-vulntrack-alive-HERO.png)

### The service mesh: Istio with STRICT mTLS

Istio was installed via Helm — control plane (`istiod`), then a dedicated
**Istio Ingress Gateway** sitting between the ALB and the app (so the ALB
still does TLS termination and WAF, but everything past that point is
mesh-native and can enforce real mTLS):

```
 ALB (TLS + WAF) ──plaintext──> Istio Ingress Gateway ──mTLS──> VulnTrack pod + Envoy sidecar
```

![istiod healthy](docs/screenshots/p5-21-istiod-healthy-running.png)

Istio's default control-plane resource requests (2Gi memory for `istiod`
alone) exceed a single `t3.micro`'s *entire* RAM — not a "needs more
nodes" problem, since no number of 1GB nodes can satisfy a pod that needs
2GB on one node. Resolved by overriding `istiod` and the gateway's
resource requests down to values that actually fit — a legitimate,
explained tradeoff for a cost-constrained demo environment, not something
a real production cluster would do.

The gateway rewire itself happened **without taking the live site down**:

![Gateway installed, routing live, zero downtime](docs/screenshots/p5-22-istio-gateway-rewire-live.png)

Enabling sidecar injection and restarting the app confirmed both
containers per pod — the app, and its injected Envoy proxy:

![Both containers per pod: app + Envoy sidecar](docs/screenshots/p5-23-sidecar-injection-2of2-running.png)

That injection alone reintroduced the pod-density problem from a second
angle: the sidecar's *own* default resource requests, combined with the
app's, exceeded what a single `t3.micro` node could satisfy for even one
pod — a real, concrete number (~640Mi combined, against roughly ~600–700Mi
of actually-usable memory per node). Fixed by right-sizing both the app's
request and the sidecar's request via `sidecar.istio.io/proxyMemory`
overrides, rather than continuing to add nodes indefinitely.

Finally, a `PeerAuthentication` policy enforcing **STRICT** mTLS —
scoped specifically to the `vulntrack` app pods, not the whole namespace,
since the Ingress Gateway (which legitimately receives plaintext from the
non-mesh ALB) also lived there at the time. (The gateway has since moved
to `istio-system` — see [Phase 6](#phase-6-proving-the-rebuild) — and the
pod-scoped selector remains the right design either way.)

![STRICT mTLS policy, confirmed active](docs/screenshots/p5-24-peerauthentication-strict-mtls.png)

The strongest proof STRICT mode is genuinely enforcing encryption: a
misconfigured STRICT policy simply refuses non-mTLS connections outright
— so the fact that the site kept responding normally after this policy
was applied *is itself* the confirmation that Gateway → Pod traffic is
real, encrypted mTLS.

### Re-pointing CI/CD at EKS

The existing GitHub Actions pipeline (Phase 4) deployed to ECS — which no
longer exists once EKS became the active environment. Redirecting it
required two separate, easy-to-miss pieces beyond just editing the
workflow file:

1. **AWS-level IAM permissions** (`eks:DescribeCluster`, so
   `aws eks update-kubeconfig` can even find the cluster)
2. **Kubernetes-level RBAC access** via an **EKS access entry** — AWS IAM
   permissions and in-cluster Kubernetes permissions are two entirely
   separate authorization systems, and having one grants nothing in the
   other

The access entry is scoped to `edit` permissions in the `default`
namespace only — enough to restart a deployment, nowhere near
cluster-admin.

While reviewing the Terraform plan for this change, a subtle mistake
would have **destroyed and recreated the entire EKS cluster** — adding an
`access_config` block without also specifying
`bootstrap_cluster_creator_admin_permissions` (a create-time-only
attribute) made Terraform think that value needed to change, which forces
full cluster replacement. Caught by reading the plan output line-by-line
before applying, rather than trusting the summary — full story in the
[Troubleshooting log](#troubleshooting-log--lessons-learned).

![CI/CD pipeline, now targeting EKS, first run succeeds](docs/screenshots/p5-26-cicd-eks-pipeline-success.png)
*Build → push to ECR → authenticate via OIDC → connect to EKS → rollout
restart, all green on the very first run against the newly-wired access
entry*

---

## Phase 6: Proving the rebuild

The [Infrastructure as code](#infrastructure-as-code) section makes a
claim: `terraform destroy` tears everything down, and `terraform apply`
rebuilds it. Phase 6 tested that claim for real — a brand-new development
machine, an empty state file, and a rebuild of the entire Phase 5 stack
from nothing — and wrote down every place the claim turned out not to
hold. Nine separate problems surfaced, and **none of them could have been
found any other way**: each one only exists on the path from zero to live.

### A development environment defined in code

Development moved off the Windows host entirely and into a Fedora VM
defined by a [`Vagrantfile`](vagrant/Vagrantfile) and a
[`provision.sh`](vagrant/provision.sh) — Java, Maven, Docker, Terraform,
kubectl, Helm, and the AWS CLI, all installed unattended. Code is edited
from VS Code on the host over **Remote-SSH**; the source tree, the build,
and every CLI tool live inside the box. Setup details are in
[`vagrant/README.md`](vagrant/README.md).

Two deliberate choices shaped it:

- **Vagrant runs on the Windows host, not inside another VM.** VirtualBox
  inside VirtualBox isn't supported, so the box sits alongside the lab
  VMs rather than nested in one.
- **The base box is pulled straight from Fedora's own mirror with a
  pinned SHA-256 checksum**, rather than by name from HashiCorp's hosted
  box registry — which is being wound down, and which a dev environment
  meant to be rebuilt later shouldn't depend on.

The first real problem was Java. Fedora 44 no longer ships a JDK 17
package, and installing Maven quietly pulls in JDK 25 as a dependency:

![Maven pulled in JDK 25](docs/screenshots/p6-01-fedora-maven-pulls-jdk25.png)

The build still succeeded — the pom's `<release>17</release>` makes JDK 25
compile against the Java 17 API —

![First build inside the box](docs/screenshots/p6-03-first-build-success-vagrant.png)

— but the app deploys onto `wildfly:31.0.1.Final-jdk17`, and building on
one JDK while running on another is exactly the drift a reproducible
environment exists to prevent. Installing Temurin 17 from Adoptium wasn't
enough on its own: Fedora derives `alternatives` priority from the version
string, so JDK 25 registers at **25000421**, and no sensible priority
outranks it:

![alternatives: 25000421 vs 3000](docs/screenshots/p6-02-alternatives-priority-25000421.png)

Fixed by pinning the selection with `alternatives --set` instead of
fighting the priority number — which also means a future `dnf upgrade`
that brings in JDK 26 can't silently reclaim the default:

![java, javac, and Maven all on Temurin 17](docs/screenshots/p6-04-temurin-17-pinned.png)

The real test of a provisioning script is deleting the machine and
running it again with no hand-fixing. `vagrant destroy` then `vagrant up`:

![Full toolchain from a clean vagrant up](docs/screenshots/p6-05-clean-vagrant-up-full-toolchain-HERO.png)
*Every tool reporting correctly on a box built from nothing but two files.
(Note the kubectl v1.33 client — two minor versions ahead of the cluster,
caught and pinned to v1.31 later in the rebuild.)*

Then the day-to-day workflow — VS Code attached to the box, building and
running the local stack inside it:

![VS Code Remote-SSH: build inside the box](docs/screenshots/p6-06-vscode-remote-ssh-build-success.png)

![Local Docker Compose stack running in the box](docs/screenshots/p6-07-docker-compose-stack-in-box.png)

### Recovering from local state

Before moving machines, the Terraform state had to be found — and the
search turned up a problem. State had always been a **local, unversioned
file**. The live `terraform.tfstate` was 183 bytes: an empty shell, zero
resources, at serial 143. The only record of what the stack had contained
was the `.backup` file beside it — 44 resources, at serial 95.

![183-byte state file vs. 99,698-byte backup](docs/screenshots/p6-08-state-file-183-bytes-vs-backup.png)

The serial numbers explain it. Terraform writes `.backup` once, at the
start of a run, then increments the serial on every state write after
that — and 143 − 95 = 48 writes, for 44 resources plus overhead. That's
the signature of a `terraform destroy` that ran to completion, not a
corrupted file. Still, the state is a claim about AWS, not proof of it,
so AWS was asked directly: no EKS or ECS clusters, no running instances,
no RDS, no load balancers, no NAT gateways, and no secrets sitting in a
pending-deletion window. Nothing orphaned, nothing billing.

One local file had been one `destroy` away from being the only
description of the infrastructure. `terraform-eks/` now keeps its state
in S3:

```hcl
terraform {
  backend "s3" {
    bucket       = "vulntrack-tfstate-825990809758"
    key          = "eks/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
    profile      = "vulntrack-terraform"
  }
}
```

The bucket has **versioning on** (so an emptied state is recoverable from
a prior version), public access fully blocked, and encryption at rest —
state files hold database credentials and secret values in plaintext.
Locking uses Terraform's native S3 lockfile rather than the older
DynamoDB lock table.

![Bucket versioning enabled](docs/screenshots/p6-09-s3-backend-versioning-enabled.png)

Two things broke on the way, both documented in the
[Troubleshooting log](#troubleshooting-log--lessons-learned): the
least-privilege Terraform IAM user had never been granted any S3
permissions, and the backend quietly authenticated as the **wrong IAM
user** — because backend blocks can't read variables, so the provider's
`var.aws_profile` never applied to it.

![terraform init against the S3 backend](docs/screenshots/p6-10-terraform-init-s3-backend.png)

### The rebuild, and what it surfaced

`terraform apply` built 46 resources and failed on exactly one. After two
fixes, the plan came back clean against live infrastructure:

![No changes: infrastructure matches configuration](docs/screenshots/p6-11-terraform-plan-no-changes.png)

![Five nodes Ready, reached from the new dev box](docs/screenshots/p6-12-kubectl-five-nodes-ready.png)

Everything between "`Apply complete!`" and a working site was where the
real problems were:

| # | What broke | Why only a rebuild exposes it | Fix |
|---|---|---|---|
| 1 | WAF association failed: `WAFNonexistentItemException` | Terraform held the old ALB's ARN as a hardcoded default. The Load Balancer Controller creates a new ALB — new ARN — every time the Ingress is recreated | Attach the Web ACL with the `alb.ingress.kubernetes.io/wafv2-acl-arn` Ingress annotation, so it follows whatever ALB exists |
| 2 | Node group showed a change on every single plan | Launch template version was the string `$Latest`; AWS stores the resolved number (`1`), so they never match | Reference `aws_launch_template.eks_nodes.latest_version` |
| 3 | kubectl v1.33 against a v1.31 cluster — outside the supported ±1 skew | The new dev box installed whatever kubectl was current; nothing tied the client version to the cluster's | Pin the Kubernetes package repo to v1.31 in `provision.sh` |
| 4 | Pods stuck `ContainerCreating`: `failed to assign an IP address` | Phase 5's `maxPods: 30` lived in the Terraform launch template and came back. VPC CNI prefix delegation had been set with `kubectl` — not in code — and didn't. Nodes **advertised** 30 pod slots they couldn't give IPs to | Re-enabled prefix delegation on the `aws-node` DaemonSet; moving it into Terraform is on the roadmap |
| 5 | Second app replica unschedulable: `Insufficient memory` on all five nodes | With every controller freshly scheduled, no node had room for a second ~450Mi app-plus-sidecar pod — each `t3.micro` exposes only ~520Mi of allocatable memory | `replicas: 1` — the honest ceiling of 1 GiB free-tier nodes carrying a service mesh |
| 6 | ALB returned `503 Backend service does not exist` | The Helm install commands were never in the repo — only their values files. The Istio gateway came back up in `istio-system` instead of `default`, and an Ingress can't reference a Service in another namespace | Moved the Ingress into `istio-system`; health check pointed at the gateway's own status port (`15021`, `/healthz/ready`) |
| 7 | DNS stayed pointed at a deleted ALB | ExternalDNS had never written its TXT ownership records for the zone-apex name — not in Phase 5 either — so it refused to update or delete records it couldn't prove were its own | `txtPrefix: "extdns-%{record_type}."`, then cleared the orphaned records once so it could recreate them with ownership |
| 8 | App pods couldn't start: missing `vulntrack-secrets` | The Kubernetes Secret was created by hand in Phase 5 and never written down | Rebuilt from Secrets Manager; the procedure is now in the runbook below |
| 9 | Backend `403` despite correct permissions | Backends can't use variables, so authentication fell through to the default AWS profile | Literal `profile` in `backend.tf` |

Two things came through intact **because** they sit outside the
Terraform lifecycle: the Route53 hosted zone (read with a data source, so
the Cloudflare NS delegation never had to change) and the ACM-imported
certificate.

Items 1, 6, and 7 are the same lesson from three directions: anything that
records the identity of something the cluster creates — an ALB's ARN, a
Service's namespace, a DNS record's owner — breaks the moment that thing
is recreated. The fixes all move the reference to the component that owns
the lifecycle.

The WAF fix, verified against the ALB that exists now rather than the one
that used to:

![WAF attached to the new ALB via annotation](docs/screenshots/p6-13-waf-attached-via-annotation.png)

![ALB target healthy on the gateway status port](docs/screenshots/p6-14-target-health-healthy.png)

![ExternalDNS ownership records at extdns-a / extdns-aaaa](docs/screenshots/p6-15-route53-extdns-txt-ownership.png)
*A and AAAA at the apex, and — for the first time in this project's
history — the TXT records that let ExternalDNS actually own them*

And back where it started:

![Live again after a full rebuild](docs/screenshots/p6-16-live-again-after-rebuild-HERO.png)
*`aws.vulntrack.app`, rebuilt from an empty state file on a dev machine
that didn't exist a week earlier*

### Rebuild runbook

Everything between `terraform apply` and a live site, in order, as it
actually worked. Run from `terraform-eks/` inside the dev box.

```bash
# 1. Infrastructure
terraform init
terraform apply
aws eks update-kubeconfig --region us-east-2 --name vulntrack-eks --profile vulntrack-terraform

# 2. VPC CNI prefix delegation (not yet in Terraform — without it,
#    nodes advertise 30 pod slots but can only assign ~4 IPs)
kubectl -n kube-system set env daemonset aws-node ENABLE_PREFIX_DELEGATION=true WARM_PREFIX_TARGET=1
kubectl -n kube-system rollout status daemonset aws-node

# 3. Helm chart repos, then the AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns
helm repo add jetstack https://charts.jetstack.io
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
kubectl apply -f lbc-service-account.yaml
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system \
  --set clusterName=vulntrack-eks --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-2 --set vpcId=$(terraform output -raw vpc_id)

# 4. ExternalDNS
helm install external-dns external-dns/external-dns -n kube-system -f external-dns-values.yaml

# 5. cert-manager + Let's Encrypt issuer
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace \
  --set crds.enabled=true --set startupapicheck.enabled=false \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$(terraform output -raw cert_manager_role_arn)"
kubectl apply -f letsencrypt-cluster-issuer.yaml

# 6. Istio (the gateway goes in istio-system — the Ingress depends on it)
helm install istio-base istio/base -n istio-system --create-namespace
helm install istiod istio/istiod -n istio-system -f istiod-values.yaml --wait
helm install istio-ingressgateway istio/gateway -n istio-system -f istio-gateway-values.yaml
kubectl label namespace default istio-injection=enabled

# 7. App secret, built from Secrets Manager
CREDS=$(aws secretsmanager get-secret-value --secret-id vulntrack-eks/db-credentials \
  --profile vulntrack-terraform --region us-east-2 --query SecretString --output text)
JWT=$(aws secretsmanager get-secret-value --secret-id vulntrack-eks/jwt-signing-key \
  --profile vulntrack-terraform --region us-east-2 --query SecretString --output text)
kubectl create secret generic vulntrack-secrets \
  --from-literal=DB_HOST="$(echo "$CREDS" | jq -r .host)" \
  --from-literal=DB_PORT="$(echo "$CREDS" | jq -r .port)" \
  --from-literal=DB_NAME="$(echo "$CREDS" | jq -r .dbname)" \
  --from-literal=DB_USERNAME="$(echo "$CREDS" | jq -r .username)" \
  --from-literal=DB_PASSWORD="$(echo "$CREDS" | jq -r .password)" \
  --from-literal=JWT_SIGNING_KEY="$JWT"

# 8. App, mesh policy, and — last — the Ingress, which creates the ALB
kubectl apply -f vulntrack-deployment.yaml -f vulntrack-service.yaml
kubectl apply -f vulntrack-certificate.yaml -f istio-routing.yaml -f peer-authentication.yaml
kubectl apply -f vulntrack-ingress.yaml
```

Checks worth running before calling it done: pods show `2/2` (sidecar
injected), the ALB target is `healthy`, the Route53 zone has `extdns-`
TXT records alongside A/AAAA, and the WAF lists the *current* ALB.

> **Note:** `vulntrack-ingress.yaml` references the ACM certificate by
> ARN. That certificate is imported (see Phase 5's manual Let's Encrypt →
> ACM bridge) and lives outside Terraform, so it survives a destroy — but
> it also has to be re-imported before it expires.

---


## CI/CD pipeline

Every push to `main` triggers [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml):

1. Builds the app with Maven
2. Authenticates to AWS via **OIDC** — no long-lived credentials stored in
   GitHub at all; the IAM role's trust policy is scoped to
   `repo:DevinCodes13/vulntrack` on the `main` branch specifically
3. Builds the Docker image and pushes it to ECR
4. Connects to the EKS cluster and performs a rolling restart, waiting for
   the rollout to finish before the workflow reports success

![CI/CD pipeline succeeding](docs/screenshots/14-github-actions-success-first-deploy.png)

Getting the OIDC trust policy right took real debugging, most notably a
GitHub token format change that broke an exact-match trust policy
(diagnosed via CloudTrail, not guesswork):

![Diagnosing the OIDC failure via CloudTrail](docs/screenshots/12-cloudtrail-oidc-diagnosis.png)
*Reading the actual `AssumeRoleWithWebIdentity` event to see exactly what
GitHub sent, rather than guessing from the generic "not authorized" error*

---

## Local development setup

### Recommended: the Vagrant dev box

A Fedora VM with the full toolchain — JDK 17, Maven, Docker, Terraform,
kubectl, Helm, AWS CLI — built unattended from
[`vagrant/`](vagrant/). Edit from VS Code on the host over Remote-SSH.
Full setup in [`vagrant/README.md`](vagrant/README.md).

```powershell
cd vagrant
vagrant plugin install vagrant-disksize
vagrant up
vagrant ssh-config --host vulntrack-dev | Out-File -Append -Encoding ascii "$env:USERPROFILE\.ssh\config"
```

Then connect VS Code to `vulntrack-dev`, clone the repo inside the box,
and follow the steps below from the integrated terminal.

### Alternative: directly on the host

#### Prerequisites

- JDK 17 (Eclipse Temurin recommended)
- Maven 3.9+
- Docker Desktop (with WSL2 backend on Windows)

![Environment fully set up](docs/screenshots/02-env-setup-success.png)
*Java, Maven, and Docker all verified in one terminal — after working
through several PATH/JAVA_HOME issues along the way*

#### First-time setup

```powershell
git clone https://github.com/DevinCodes13/vulntrack.git
cd vulntrack
mvn clean package
docker compose up -d --build
```

The app is available at `http://localhost:8080/vulntrack/` (dashboard) and
`http://localhost:8080/vulntrack/api` (REST API). The WildFly admin
console is at `http://localhost:9990`.

![Local dashboard with real findings](docs/screenshots/16-dashboard-local-with-findings.png)

#### Rebuilding after code changes

```powershell
mvn clean package
docker compose down
docker compose up -d --build
```

---

## Troubleshooting log & lessons learned

Kept here rather than smoothed over, since debugging real infrastructure
issues is a meaningful part of what this project demonstrates.

### Phase 1–4

- **Maven archetype plugin failed outright** (`MissingProjectException`,
  instant failure, no clear cause) — scaffolded the project by hand
  instead of relying on `mvn archetype:generate`.
- **Adding a `NOT NULL` column via Hibernate's `hbm2ddl.auto=update`**
  failed against a table that already had rows with null values in that
  column. Resolved by clearing conflicting test data before redeploying —
  a real limitation of auto-migration, and part of why production systems
  use versioned migration tools (Flyway/Liquibase) instead.
- **JAX-RS `UriInfo.getPath()` leading-slash inconsistency** caused the
  auth filter's path-exclusion check to silently fail, blocking even the
  registration endpoint — fixed by checking both `"auth/"` and `"/auth/"`.
- **CDI-proxied JAX-RS resources cannot reliably inject
  `ContainerRequestContext`** — RESTEasy throws
  `RESTEASY003880: Unable to find contextual data`. Resolved with a
  `@RequestScoped` CDI bean (`RequestUserContext`) shared between the auth
  filter and the resource classes.
- **Notepad silently appends `.txt`** to filenames without a recognized
  extension (`Dockerfile` → `Dockerfile.txt`) unless the filename is
  quoted in the Save As dialog or "All Files" is selected explicitly.
- **WildFly's embedded-server CLI bootstrap can silently prevent real
  deployment.** Copying the WAR into `standalone/deployments/` *before*
  running the offline `datasource.cli` configuration step causes WildFly
  to auto-deploy it during that embedded boot and bake an "already
  deployed" marker into the image layer, so the real container never
  deploys the app at runtime, with no error logged anywhere. Fixed by
  sequencing the Dockerfile so the WAR is copied in only *after* the CLI
  step completes.
- **ALB health checks cannot carry authentication headers.** Once JWT auth
  was added, the load balancer's health check to `/api/ping` started
  failing with 401s. The health check endpoint has to be explicitly
  exempted from the auth filter — application security and infrastructure
  health monitoring are different concerns with different requirements.
- **A prior project's hardened IAM policy blocked this one.** Reusing an
  IAM user from an earlier AWS hardening project for Terraform failed
  because its policy has an explicit `Deny` on security-group rule
  changes — which always overrides any `Allow`, even from a different
  attached policy. Resolved by creating a separate, purpose-scoped IAM
  user rather than loosening a different project's intentionally hardened
  policy.
- **GitHub's OIDC token `sub` claim format changed** to include immutable
  numeric owner/repo IDs rather than plain names, breaking an exact-match
  IAM trust policy written against the older format. Diagnosed via
  CloudTrail's `AssumeRoleWithWebIdentity` event history rather than
  guessing from the generic "not authorized" error. Resolved with a
  `StringLike` wildcard pattern that tolerates both formats.
- **A region placeholder in an IAM policy resource ARN went uncorrected**
  (`us-east-1` instead of the actual `us-east-2`), causing the GitHub
  Actions role to authenticate successfully via OIDC but still be denied
  `ecr:InitiateLayerUpload` — a reminder that region-scoped ARNs in policy
  templates need to be checked against the actual deployment region.
- **`docker login --password-stdin` failed with a 400 Bad Request** via
  PowerShell piping, despite valid credentials (confirmed by testing with
  `--password` directly instead) — a transport/encoding quirk specific to
  that Docker Desktop/PowerShell combination, not a credentials problem.
- **Destroying and recreating Secrets Manager entries hits AWS's default
  30-day recovery window** — a `terraform destroy` schedules secrets for
  deletion rather than purging them immediately. Setting
  `recovery_window_in_days = 0` makes destroy/recreate cycles clean.
- **IAM least-privilege is iterative, not perfect on the first try.**
  Building each Terraform IAM policy surfaced a long tail of missing
  read-back permissions that only appear once Terraform actually tries to
  read a resource back into state after creating it. Rather than chase
  each one individually, AWS's managed `ReadOnlyAccess` policy was layered
  on top of the narrower custom policy.

### Phase 5

- **Cloudflare Registrar contractually forbids changing nameservers.**
  Discovered after registering `vulntrack.app` there specifically for the
  Route53 integration — Cloudflare's terms require using their own
  nameservers, and newly-registered domains carry a mandatory 60-day
  ICANN transfer lock regardless of registrar. Resolved by delegating a
  subdomain (`aws.vulntrack.app`) to Route53 via an `NS` record, rather
  than waiting out the lock or switching registrars.
- **AWS account "Free Tier" flags restrict more than just billing.**
  Beyond blocking Route53 domain registration outright, the same flag
  blocked launching non-free-tier EC2 instance types (`t3.medium` failed
  with "not eligible for Free Tier"), forcing the entire EKS node group
  onto `t3.micro` — which then drove several of the harder problems below.
- **EKS managed node groups cap pod density by instance networking
  capacity, not CPU/memory.** `t3.micro` supports only 4 pod IPs per node
  — a ceiling completely invisible in `kubectl top` or resource
  dashboards, only surfacing as `FailedScheduling: ... Too many pods`.
  Fixed properly (not just by adding nodes indefinitely) by enabling VPC
  CNI prefix delegation and a custom launch template overriding kubelet's
  `maxPods`, raising the real per-node ceiling to 30.
- **A custom EKS node-group launch template requires IAM permissions no
  standard node group ever needs**: `ec2:CreateLaunchTemplate`, and
  separately `ec2:RunInstances` — EKS validates that the *calling IAM
  principal* (not just its own service role) could launch an instance
  with that template, before delegating the actual launch internally.
  Neither permission had ever been needed before this specific change.
- **A `terraform apply` that reported success wasn't actually
  succeeding.** Two consecutive "Apply complete!" results were followed
  by the created resources vanishing entirely from both Terraform state
  and AWS's own API. Root-caused by reading a *complete*, unedited log
  rather than a summarized one: an explicit `Error: creating EKS Node
  Group ... CREATE_FAILED` block had been present in the output the whole
  time. Terraform's own provider automatically rolls back (deletes) a
  node group that fails its post-creation health check — which looked
  identical to a mysterious external process deleting things, until the
  actual error text was read directly. The underlying cause was a
  malformed `nodeadm` YAML config, produced by Terraform heredoc
  indentation stripping not behaving as expected; rewritten using
  explicit zero-indentation string concatenation instead.
- **Istio's default control-plane and gateway resource requests assume
  real infrastructure**, not a single `t3.micro`. `istiod`'s default 2Gi
  memory request exceeds an entire node's total RAM — not fixable by
  adding more nodes, since a pod's request has to fit on *one* node.
  Resolved by explicitly overriding `istiod` and the gateway's resource
  requests to fit, with the tradeoff clearly documented rather than
  silently normalized.
- **ExternalDNS silently generates zero DNS records with no error**, if
  its `sources` config doesn't explicitly include `ingress` (the Helm
  chart's default doesn't) — and separately, if the target `Ingress`
  relies on the deprecated `kubernetes.io/ingress.class` annotation
  instead of `spec.ingressClassName`. Both symptoms look identical
  ("All records are already up to date," forever) and were only
  distinguished by turning on debug-level logging and reading the literal
  per-resource skip reason (`"No endpoints could be generated from
  ingress/default/vulntrack"`) rather than guessing from the calm,
  error-free info-level logs.
- **A Terraform plan that looked like a routine config update would have
  destroyed the entire EKS cluster.** Adding an `access_config` block to
  enable EKS access entries, without also specifying the create-time-only
  `bootstrap_cluster_creator_admin_permissions` attribute, made Terraform
  treat that value as changing — which forces full cluster replacement
  (cascading into the OIDC provider and every IRSA trust policy that
  references it). Caught by reading the complete plan output before
  applying and specifically checking for `must be replaced` versus
  `will be updated in-place`, rather than trusting a plan summary line.
- **AWS-level IAM permissions and in-cluster Kubernetes RBAC are two
  entirely separate authorization systems.** Granting the GitHub Actions
  IAM role `eks:DescribeCluster` was necessary but not sufficient for the
  CI/CD pipeline to actually run `kubectl` commands against the cluster —
  it also needed an explicit **EKS access entry** mapping that IAM
  principal to real Kubernetes RBAC permissions, since IAM permissions
  alone grant no visibility or control inside the cluster itself.

### Phase 6

- **An empty state file isn't necessarily a lost one.** The local
  `terraform.tfstate` was 183 bytes with zero resources; the `.backup`
  beside it held 44. Rather than assume the worst, the serial numbers
  were compared (95 in the backup, 143 live — 48 writes, consistent with
  a destroy that ran to completion), and then AWS was queried directly
  for every resource type the backup listed. Nothing orphaned. The fix
  for the underlying risk was a versioned S3 backend, not better luck.
- **Terraform backend blocks can't use variables — and the failure
  doesn't say so.** The AWS provider authenticated through
  `var.aws_profile` correctly, but the S3 backend silently fell back to
  the `default` profile: a different, far less privileged IAM user. The
  error was a bare `403 Forbidden` on `HeadObject`, while the same call
  run by hand with the right profile returned a correct `404`. Only
  `TF_LOG=DEBUG` named the actual principal making the request. Fixed
  with a literal `profile` in `backend.tf`.
- **A hardcoded reference to something Kubernetes creates is a rebuild
  waiting to fail.** The WAF association's `alb_arn` default pointed at
  an ALB the Load Balancer Controller had deleted along with the old
  Ingress. Moved to the `alb.ingress.kubernetes.io/wafv2-acl-arn`
  annotation, which re-attaches the Web ACL whenever the controller
  recreates the ALB.
- **`$Latest` in a launch template produces a permanent diff.** AWS
  resolves and stores the version number; Terraform keeps comparing the
  literal string. Every plan proposed the same change, and every apply
  "fixed" it. `latest_version` resolves on the Terraform side instead.
- **A node's advertised pod capacity and its real capacity can
  disagree.** Phase 5's `maxPods: 30` came back with the launch template,
  so `kubectl` reported 30 allocatable pods per node. Prefix delegation —
  the part that actually supplies the IP addresses — had been applied
  with `kubectl set env` and wasn't in code. The result looked like an
  unrelated cert-manager failure (a Helm `startupapicheck` timeout) until
  the pod's events showed `failed to assign an IP address to container`.
- **An Ingress backend can't cross namespaces, and the ALB still gets
  built.** With the Istio gateway installed in `istio-system` and the
  Ingress in `default`, the Load Balancer Controller created the ALB,
  both listeners, the certificate binding, and the WAF association — then
  a listener rule returning a fixed `503 Backend service does not exist`,
  because it had no Service to build a target group from.
  `kubectl describe ingress` showed it directly:
  `services "istio-ingressgateway" not found`. The deeper cause: Phase 5
  committed the Helm *values* files but never the install commands, so
  the namespace was never written down. The
  [rebuild runbook](#rebuild-runbook) fixes that.
- **Health-checking an app path through a proxy tests the wrong thing.**
  Once the target group existed, it was `unhealthy` with
  `ResponseCodeMismatch` — the ALB was probing `/vulntrack/api/ping` on
  the gateway pod. Pointed it at the gateway's own readiness endpoint
  (`15021`, `/healthz/ready`) instead; end-to-end reachability is a
  separate check.
- **ExternalDNS "All records are already up to date" has a third
  meaning.** Phase 5 hit it twice with two different causes; Phase 6
  found another. With `--registry=txt` configured correctly, ExternalDNS
  still wrote no TXT ownership records for the zone-apex name — its
  change sets contained only A and AAAA — and it then refused to update
  or delete those records because it couldn't prove it owned them
  (`missing owner label` at debug level). CloudTrail confirmed ExternalDNS
  itself had created them. Setting `txtPrefix: "extdns-%{record_type}."`
  placed the registry records at `extdns-a` / `extdns-aaaa` inside the
  zone, after which ownership worked. This had been silently broken since
  Phase 5 — and explains why the Phase 5 teardown needed Route53 records
  deleted by hand.
- **Fedora 44 dropped JDK 17, and Maven depends on JDK 25.** The build
  succeeded anyway thanks to `<release>17</release>`, but the runtime is
  a JDK 17 WildFly image. Temurin 17 installed cleanly and still lost the
  default, because Fedora sets `alternatives` priority from the version
  string (25000421). Pinned with `alternatives --set`.

---

## Roadmap

- [x] Phase 1 — Maven/Jakarta EE scaffold, WildFly deployment, first REST endpoint
- [x] Phase 2 — PostgreSQL integration via custom WildFly datasource module
- [x] Phase 3 — JPA entity model, full CRUD REST API
- [x] Phase 3.5 — JWT authentication, bcrypt password hashing, role-based access control
- [x] Phase 4 — Infrastructure as code (Terraform), OIDC-based GitHub Actions CI/CD pipeline, minimal frontend dashboard, verified live end-to-end on AWS (ECS/Fargate)
- [x] Phase 5 — Re-architected onto EKS: Route53 + ExternalDNS, Let's Encrypt via cert-manager (bridged into ACM), AWS WAF, and a full Istio service mesh with STRICT mutual TLS between pods. CI/CD pipeline re-pointed from ECS to EKS with proper Kubernetes RBAC access.
- [x] Phase 6 — Reproducible Vagrant/Fedora dev environment; Terraform state migrated to a versioned S3 backend; full destroy-and-rebuild of the EKS stack from an empty state file, with nine rebuild-only defects found and fixed and a written rebuild runbook
- [ ] Next — VPC CNI prefix delegation in Terraform (currently a manual `kubectl` step), Helm installs scripted rather than documented, `terraform-ecs/` moved to the S3 backend, automated Let's Encrypt → ACM renewal (currently a manual bridge), External Secrets Operator instead of manually-synced Kubernetes Secrets, tighter IAM scoping on the remaining broad grants

---

## Author

Devin Phillips — [github.com/DevinCodes13](https://github.com/DevinCodes13)
