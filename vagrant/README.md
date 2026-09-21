# VulnTrack dev box

A Fedora 44 VM with everything needed to build, run, and deploy
VulnTrack — defined entirely by the [`Vagrantfile`](Vagrantfile) and
[`provision.sh`](provision.sh) in this folder. Destroy it and bring it back
up, and you get the same environment with no hand-fixing.

Background on why it exists, and what building it surfaced, is in
[Phase 6 of the main README](../README.md#phase-6-proving-the-rebuild).

## What it installs

| Tool | Version | Source |
|---|---|---|
| JDK | Temurin 17 (pinned as default) | Adoptium |
| Maven | 3.9 | Fedora |
| Docker + Compose plugin | current | Docker CE repo |
| Terraform | current | HashiCorp repo |
| kubectl | v1.31 (matches the EKS cluster) | pkgs.k8s.io |
| Helm | current | Fedora |
| AWS CLI | v2 | Fedora |

The VM gets 4 vCPUs, 8 GB RAM, and a 60 GB disk, and forwards guest port
8080 to host `localhost:8080` (the app) and 5432 to host `15432` (Postgres).

## Requirements (Windows host)

- VirtualBox
- Vagrant — `winget install --id Hashicorp.Vagrant -e`
- The disk-resize plugin — `vagrant plugin install vagrant-disksize`
- VS Code with the **Remote - SSH** extension (`ms-vscode-remote.remote-ssh`)

Run Vagrant on the physical host, not inside another VirtualBox VM —
nested VirtualBox isn't supported.

## First run

From this folder, in a **non-elevated** PowerShell:

```powershell
vagrant up
```

The first run downloads the Fedora base box and installs the whole
toolchain — about 10–15 minutes. It ends by printing every tool's version.

Then register the box with SSH so VS Code can find it:

```powershell
vagrant ssh-config --host vulntrack-dev | Out-File -Append -Encoding ascii "$env:USERPROFILE\.ssh\config"
```

Make sure the file ended with a newline before appending — otherwise
`Host vulntrack-dev` fuses onto the previous line and SSH rejects the whole
config. After any `vagrant destroy`, delete the old `vulntrack-dev` block
and regenerate it; the key and port change.

## Working in the box

In VS Code: `F1` → **Remote-SSH: Connect to Host** → `vulntrack-dev`. The
status bar should read `SSH: vulntrack-dev`; the integrated terminal is
now a shell inside Fedora. Install the Java and Docker extensions *in the
remote window* — local and remote extensions are separate.

First time inside:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@users.noreply.github.com"
git clone https://github.com/DevinCodes13/vulntrack.git ~/vulntrack
cd ~/vulntrack
mvn clean package
docker compose up -d --build
```

Then *File → Open Folder → `/home/vagrant/vulntrack`*. The app is at
`http://localhost:8080/vulntrack/` from the host browser, either through
Vagrant's port forward or VS Code's **Ports** panel.

For AWS and Terraform work, copy credentials in from PowerShell on the host:

```powershell
scp -r "$env:USERPROFILE\.aws" vulntrack-dev:~/.aws
```

```bash
chmod 600 ~/.aws/credentials
aws sts get-caller-identity --profile vulntrack-terraform
```

## Design decisions

**The base box comes from Fedora's own mirror, by URL, with a pinned
SHA-256** — not by name from HashiCorp's hosted box registry, which is
being wound down. When Fedora releases a new version, update `box_url`
and the checksum together.

**Java 17 is pinned with `alternatives --set`, not by priority.** Fedora
44 no longer packages JDK 17, and Maven pulls in JDK 25 as a dependency.
Fedora assigns `alternatives` priority from the version string — JDK 25
registers at 25000421 — so a priority-based install of Temurin 17 loses.
`--set` pins it regardless of what future upgrades bring in. The match
matters because the app's runtime image is `wildfly:31.0.1.Final-jdk17`.

**kubectl is pinned to the cluster's minor version.** Kubernetes supports
one minor version of client/server skew; "whatever's current" drifted two
versions ahead of the EKS cluster. Update `K8S_MINOR` in `provision.sh`
whenever the cluster is upgraded.

**No synced folder.** The Fedora cloud box ships without VirtualBox Guest
Additions, and the code is meant to live in the box anyway — VS Code edits
it in place over SSH.

**Line endings are enforced as LF** (`.gitattributes`). A `provision.sh`
checked out with Windows CRLF endings fails inside Linux with a confusing
"bad interpreter" error.

## Everyday commands

```powershell
vagrant up        # start (provisioning only runs the first time)
vagrant halt      # clean shutdown — keeps everything
vagrant reload    # reboot, e.g. after a kernel update
vagrant provision # re-run provision.sh on the existing box
vagrant destroy   # delete the VM entirely — rebuild with vagrant up
```

`vagrant/.vagrant/` holds machine-local runtime state and the box's
generated SSH key. It's gitignored and should stay that way.

## Tips

- A command using `sudo`, `dnf`, heredocs, or `/etc/` paths is Linux-only —
  run it in the VS Code terminal or via `vagrant ssh -c "..."`, never in
  PowerShell directly.
- If pasted commands arrive wrapped in `[200~ … ~`, disable bracketed paste:
  `echo 'set enable-bracketed-paste off' >> ~/.inputrc` and open a new
  terminal.
