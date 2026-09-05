# VulnTrack

A vulnerability and asset tracking web application built as a classic Java
3-tier stack — Jakarta EE on WildFly (JBoss), PostgreSQL, and a Dockerized
build/deploy pipeline. Built as a portfolio project to demonstrate full-stack
Java development, application-server administration, and applied security
(JWT auth, bcrypt hashing, role-based access control) in one connected system.

> This project ties together earlier work from my
> [home lab / SOC](#) and
> [AWS cloud security hardening](#) projects: VulnTrack is designed to track
> findings from tools like OpenVAS/Greenbone, the same vulnerability scanner
> used in my Vulnerability Management lab project.

---

## Table of contents

- [Architecture](#architecture)
- [Tech stack](#tech-stack)
- [Data model](#data-model)
- [API reference](#api-reference)
- [Authentication & authorization](#authentication--authorization)
- [Local development setup](#local-development-setup)
- [Build & deploy](#build--deploy)
- [Troubleshooting log](#troubleshooting-log--lessons-learned)
- [Roadmap](#roadmap)

---

## Architecture

Classic 3-tier design:

- **Presentation tier**: REST API (JSON), consumed by curl/Postman today,
  a frontend planned for Phase 4
- **Application tier**: Jakarta EE (JAX-RS + CDI) deployed on WildFly,
  containerized via a custom Docker image
- **Data tier**: PostgreSQL, running as its own container, with a
  hand-installed WildFly datasource module (not the default H2 example)

```
 Client (curl / future UI)
        |
        v
 WildFly (JAX-RS, CDI, JWT auth filter)
        |
        v
 PostgreSQL (via custom JDBC module + JNDI datasource)
```

Everything runs locally today via Docker Compose. Phase 4 will move this to
AWS (ECS + RDS) behind a CI/CD pipeline.

![Environment setup](docs/screenshots/PLACEHOLDER-env-setup.png)
*java/mvn/docker version check — environment ready*

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
| Build | Maven |
| Containerization | Docker, Docker Compose |
| Planned CI/CD | GitHub Actions → AWS ECS/RDS |

---

## Data model

Four core entities: `Asset`, `Vulnerability`, `Finding` (the join entity
linking a vulnerability to an asset with a status and remediation deadline),
and `AppUser`.

See [`docs/diagrams/vulntrack-er-diagram.md`](docs/diagrams/vulntrack-er-diagram.md)
for the full ER diagram (renders automatically on GitHub).

![Schema verification](docs/screenshots/PLACEHOLDER-schema-tables.png)
*`\dt` output confirming all four tables exist in Postgres*

![Foreign key verification](docs/screenshots/PLACEHOLDER-finding-schema.png)
*`\d finding` output confirming foreign key relationships*

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
| GET / POST / PUT / DELETE | `/findings`, `/findings/{id}` | Yes | Accepts `assetId` / `vulnerabilityId` / `assignedUserId` in the request body; server resolves the actual entities |

![CRUD verification](docs/screenshots/PLACEHOLDER-crud-get-all.png)
*GET requests across all four entities, including nested relationship data on `/findings`*

![Write verification](docs/screenshots/PLACEHOLDER-post-asset.png)
*POST creating a new asset, confirmed with 201 Created*

---

## Authentication & authorization

- Passwords are hashed with bcrypt before storage — never stored plain
- `POST /auth/login` returns a JWT signed with HS384, containing the
  username (`sub`) and role (`role`) claims
- A `ContainerRequestFilter` (`AuthFilter`) validates the
  `Authorization: Bearer <token>` header on every request except
  `/auth/*`
- Role checks are enforced per-endpoint using a `@RequestScoped` CDI bean
  (`RequestUserContext`) shared between the filter and the resource classes
  — see [Troubleshooting log](#troubleshooting-log--lessons-learned) for why
  this pattern was necessary
- Example: `DELETE /assets/{id}` is restricted to users with the `ADMIN`
  role; `ANALYST` users receive `403 Forbidden`

![Auth flow — unauthorized](docs/screenshots/PLACEHOLDER-401-unauthorized.png)
*Calling a protected endpoint with no token → 401*

![Auth flow — authorized](docs/screenshots/PLACEHOLDER-200-with-token.png)
*Same endpoint, with a valid JWT → 200*

![RBAC enforcement](docs/screenshots/PLACEHOLDER-403-vs-204.png)
*Same DELETE call: ANALYST role → 403 Forbidden, ADMIN role → 204 No Content*

> **Note on the JWT signing key**: `JwtUtil.java` uses a hardcoded
> development-only secret, clearly commented as such in the source. In a
> real deployment this would move to AWS Secrets Manager or an environment
> variable — this is a known, intentional shortcut for local development,
> not an oversight.

---

## Local development setup

### Prerequisites

- JDK 17 (Eclipse Temurin recommended)
- Maven 3.9+
- Docker Desktop (with WSL2 backend on Windows)

### First-time setup

```powershell
git clone <this-repo>
cd vulntrack
mvn clean package
docker compose up -d --build
```

The WildFly admin console is available at `http://localhost:9990`.
The API is available at `http://localhost:8080/vulntrack/api`.

### Rebuilding after code changes

```powershell
mvn clean package
docker compose down
docker compose up -d --build
```

---

## Build & deploy

The application builds to a WAR file (`target/vulntrack.war`) via Maven,
which is mounted into a custom WildFly Docker image. That image is built
from a `Dockerfile` that:

1. Starts from the official `quay.io/wildfly/wildfly` image
2. Copies in a hand-installed PostgreSQL JDBC module
   (`modules/org/postgresql/main/`)
3. Runs a WildFly CLI script (`datasource.cli`) at build time to register
   the driver and create the `VulnTrackDS` datasource

This means the datasource configuration is baked into the image itself —
no manual admin-console clicking required to stand up a working environment.

![WildFly + Postgres running](docs/screenshots/PLACEHOLDER-datasource-bound.png)
*Both `ExampleDS` (default) and `VulnTrackDS` (custom) bound successfully*

![Connection test](docs/screenshots/PLACEHOLDER-connection-test.png)
*`test-connection-in-pool` confirming a live connection to Postgres*

---

## CI/CD pipeline

Every push to `main` triggers [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml), which:

1. Builds the app with Maven
2. Authenticates to AWS via **OIDC** — GitHub Actions assumes a scoped IAM
   role (`github-actions-vulntrack-deploy`) using a short-lived identity
   token, with **no long-lived AWS credentials stored in GitHub at all**
3. Builds the Docker image and pushes it to ECR (tagged both `latest` and
   with the commit SHA)
4. Forces a new ECS deployment and waits for the service to report stable
   before the workflow finishes

The IAM role's trust policy is scoped specifically to
`repo:DevinCodes13/vulntrack` on the `main` branch — no other repository or
branch can assume it, even if the OIDC provider were somehow reused
elsewhere in the account.

![CI/CD pipeline success](docs/screenshots/PLACEHOLDER-actions-success.png)
*A full build → push → deploy run completing successfully, triggered
automatically by a `git push`*

> **Note on the live URL**: the ALB's public DNS name changes every time
> the infrastructure is destroyed and recreated via Terraform (a deliberate
> cost-control choice — the environment isn't left running 24/7). The
> current URL is available via `terraform output alb_dns_name` after an
> apply, rather than hardcoded here.

## Troubleshooting log & lessons learned

Kept here rather than smoothed over, since debugging real infrastructure
issues is a meaningful part of what this project demonstrates.

- **Maven archetype plugin failed outright** (`MissingProjectException`,
  0.07s instant failure) with no clear network cause. Rather than keep
  chasing it, the project was scaffolded manually — writing `pom.xml` and
  the folder structure by hand instead of relying on `mvn archetype:generate`.
- **`mvn dependency:copy` failed** to resolve `-Dartifact` correctly in this
  Maven version. Worked around by temporarily adding the dependency to
  `pom.xml`, letting Maven resolve it normally, then copying the JAR out of
  the local `.m2` repository.
- **Adding a `NOT NULL` column via Hibernate's `hbm2ddl.auto=update`** failed
  against a table that already had rows with null values in that column —
  a real limitation of auto-migration, and part of why production systems
  use versioned migration tools (Flyway/Liquibase) instead. Resolved here by
  clearing test data before redeploying; a planned Phase 4 improvement.
- **JAX-RS `UriInfo.getPath()` leading-slash inconsistency** caused an auth
  filter's path-exclusion check (`path.startsWith("auth/")`) to silently
  fail, blocking even the registration endpoint. Fixed by checking both
  `"auth/"` and `"/auth/"`.
- **CDI-proxied JAX-RS resources cannot reliably inject
  `ContainerRequestContext`** as a method parameter or even as a field —
  RESTEasy throws `RESTEASY003880: Unable to find contextual data`. Resolved
  by introducing a `@RequestScoped` CDI bean (`RequestUserContext`) that the
  auth filter populates and resource classes inject directly, instead of
  relying on framework-level request context injection.
- **Notepad silently appends `.txt`** to filenames without a recognized
  extension (e.g. `Dockerfile` → `Dockerfile.txt`) unless the filename is
  quoted in the Save As dialog or "All Files" is selected explicitly.
- **WildFly's embedded-server CLI bootstrap can silently prevent real
  deployment.** Copying the WAR into `standalone/deployments/` *before*
  running the offline `datasource.cli` configuration step causes WildFly to
  auto-deploy it during that embedded boot and bake an "already deployed"
  marker into the image layer — so the real container never deploys the app
  at runtime, with no error logged anywhere. Fixed by sequencing the
  Dockerfile so the WAR is copied in only *after* the CLI step completes.
- **ALB health checks cannot carry authentication headers.** Once JWT auth
  was added, the load balancer's health check to `/api/ping` started
  failing with 401s, since it can't present a bearer token. The health
  check endpoint has to be explicitly exempted from the auth filter —
  a good reminder that infrastructure health monitoring and application
  security are different concerns with different requirements.
- **GitHub's OIDC token `sub` claim format changed** to include immutable
  numeric owner/repo IDs (`repo:owner@org_id/repo@repo_id:ref:...`) rather
  than plain names, which broke an exact-match IAM trust policy written
  against the older format. Diagnosed via CloudTrail's `AssumeRoleWithWebIdentity`
  event history (the `principalId` field shows the exact string GitHub
  sent) rather than guessing from the generic "not authorized" error.
  Resolved with a `StringLike` wildcard pattern that tolerates both formats.
- **A region placeholder in an IAM policy resource ARN went uncorrected**
  (`us-east-1` instead of the actual `us-east-2`), causing the GitHub
  Actions role to authenticate successfully via OIDC but still be denied
  `ecr:InitiateLayerUpload` — a reminder that region-scoped ARNs in policy
  templates need to be checked against the actual deployment region, not
  left as a generic placeholder.
- **Destroying and recreating Secrets Manager entries hits AWS's default
  30-day recovery window** — a `terraform destroy` schedules secrets for
  deletion rather than purging them immediately, so a following
  `terraform apply` fails with "already scheduled for deletion." Setting
  `recovery_window_in_days = 0` makes destroy/recreate cycles clean.

---

## Roadmap

- [x] Phase 1 — Maven/Jakarta EE scaffold, WildFly deployment, first REST endpoint
- [x] Phase 2 — PostgreSQL integration via custom WildFly datasource module
- [x] Phase 3 — JPA entity model, full CRUD REST API
- [x] Phase 3.5 — JWT authentication, bcrypt password hashing, role-based access control
- [x] Phase 4 — Infrastructure as code (Terraform: VPC, RDS, ECS Fargate, ALB, Secrets Manager), OIDC-based GitHub Actions CI/CD pipeline (build → push to ECR → deploy to ECS), verified live end-to-end
- [ ] Phase 4+ — TLS/HTTPS on the ALB, a dashboard UI, tightened IAM scoping on remaining broad grants

---

## Author

Devin Phillips — [github.com/DevinCodes13](https://github.com/DevinCodes13)
