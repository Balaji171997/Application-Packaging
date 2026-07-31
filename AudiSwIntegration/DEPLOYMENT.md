# Deployment plan — Audi SCCM Integration Tool

Everything Audi has to provide, what we install, and what the security review will
ask about. Two delivery options are described; **the engine, the config and the
window are identical in both** — only how a job reaches the server differs.

Repeat all of it **once per environment** (ICZ, INA, PCZ). The three environments
are separate AD domains, so nothing can be shared between them.

---

## 1. The two options in one paragraph

**Option A — live connection.** The window talks straight to a small "counter"
registered on a server in the SCCM zone. Work starts immediately and the packager
watches it happen. Needs one firewall channel opened.

**Option B — drop folder.** The window writes the job into a folder in the secure
zone. A scheduled task inside that zone collects it a few minutes later and runs
it. Nothing connects inward, so no firewall change — but the packager gets a
result later instead of watching it.

Their own diagram ("Barrier", *copy content to secure zone*) points at **B**.
Decide this with Audi before rollout; it changes only the transport.

---

## 2. Common to both options

### 2.1 Accounts and groups — the AD team

| Item | Example | Notes |
|---|---|---|
| Service account (gMSA) | `DEAUDI005T\svc-swintegration$` | One per environment. Password created and rotated by AD, never seen by anyone. Note the trailing `$`. |
| Servers allowed to use it | the endpoint / watcher host | `PrincipalsAllowedToRetrieveManagedPassword` |
| Operator group | `DEAUDI005T\G-Audi-SwIntegration-Operators` | The packagers. **No rights of its own.** |

```powershell
# AD team, once per environment
New-ADServiceAccount -Name svc-swintegration -DNSHostName svc-swintegration.audi.vwg5t `
    -PrincipalsAllowedToRetrieveManagedPassword 'AUDIINSA1298$'
New-ADGroup -Name G-Audi-SwIntegration-Operators -GroupScope Global -Path 'OU=...'

# on the server, once
Install-ADServiceAccount -Identity svc-swintegration
Test-ADServiceAccount    -Identity svc-swintegration      # must return True
```

**Why a gMSA and not an ordinary service account.** A gMSA has no password a human
ever holds, and it rotates automatically. It also has *real* credentials, so the
session can reach onward resources — the SMS Provider, the content share, the ARS
service. A JEA *virtual account* could not: it would appear on the network as the
computer account.

If Audi refuses gMSA, the fallback is an ordinary service account with
`RunAsCredential` in the same session configuration. The password then exists on
that one server only — never on a packager's PC. Everything else is unchanged.

### 2.2 Permissions for the service account

| Where | What | Why |
|---|---|---|
| **SCCM** | A security role equivalent to **Application Administrator**, limited to the security scopes and limiting collections named in the environment file | create the application, deployment type, collections, deployments, scopes, folder moves |
| **Content share** | Read (Modify if the tool is later asked to copy content) | preflight checks the source exists; the deployment type points at it |
| **ARS / SPML** | Create and delete groups in the target OU only | the access group |
| **Endpoint host** | *Nothing.* Not a local administrator. | it only needs to be the RunAs identity |
| **Domain** | *Nothing.* Not a Domain Admin. | — |

**What the operator group gets: membership, and nothing else.** No SCCM rights, no
share rights, no local rights. This is the point of the design — after rollout the
packagers' personal MECM admin accounts can be withdrawn.

### 2.3 What we install on the server

```
C:\Program Files\Audi\SwIntegration\        the engine and its config
C:\ProgramData\Audi\SwIntegration\Logs\     per-job logs and job.json
C:\ProgramData\Audi\SwIntegration\Transcripts\   session transcripts (option A)
```

Nothing else on the server is modified. No SCCM setting is changed. Removal is one
command and leaves the environment exactly as it was.

### 2.4 What the packager needs — identical in both options

- A domain-joined PC, signed in with their normal account
- Membership of the operator group
- A shortcut to the tool on a share
- **No** SCCM console, **no** SCCM rights, **no** local admin, **no** password, nothing installed

> **The most common support call.** Group membership is read from the Windows
> **logon token**. Someone newly added must sign out and back in, or they will be
> refused while looking at their own name in the group. Put this in the handover.

---

## 3. Extra for Option A — live connection

### 3.1 The firewall rule

**What it is.** A firewall rule names **machines and a port**, never people. It
cannot say "only Anna". It says:

> *source: the packaging workstation subnet — destination: this one server —
> port: TCP 5985 (or 5986) — action: allow*

Scope it to the packaging subnet, **not** the whole domain.

| Port | What it is | When to choose it |
|---|---|---|
| **5985** | WinRM over HTTP | Default. Despite "HTTP", the payload is **encrypted by Kerberos at message level** — it is not plaintext. |
| **5986** | WinRM over HTTPS | If policy mandates TLS on the wire. Needs a server certificate and a listener. |

**Is opening it risky?** Reaching the port grants nothing on its own. Anyone who
connects must still (a) authenticate as a domain user and (b) be in the operator
group, or they are refused before any of our code runs. And a permitted user can
only run our handful of commands — no shell, no file browsing, no access to the
rest of the server.

**So the control that matters is the group, not the port.** That is the thing to
govern, review and re-certify.

**Answers for the security review**

| Question | Answer |
|---|---|
| Is this a new protocol? | No. WinRM is built into Windows Server and enabled by default since 2012. It is Microsoft's standard management channel. |
| Is traffic encrypted? | Yes — Kerberos encrypts the payload on 5985; use 5986 if TLS on the wire is required. |
| Can a caller run arbitrary code? | No. `SessionType = RestrictedRemoteServer`, `LanguageMode = NoLanguage`, and only the commands in the role capability file exist. |
| Can a caller reach the file system or other servers? | No. No providers, no drives, no external commands. |
| Is CredSSP or delegation used? | **No.** Neither. The session has its own credentials; nothing is forwarded. |
| What is logged? | Every session is transcribed by Windows, independently of the tool's own per-job log and `job.json`. |
| Blast radius if the group is over-populated? | A member can integrate and remove packages. They cannot alter SCCM otherwise, read the share, or touch the server. |

### 3.2 The registration

One command, on the server, by a local administrator, under a change record:

```powershell
.\Install-AudiSwEndpoint.ps1 `
    -Gmsa          'DEAUDI005T\svc-swintegration$' `
    -OperatorGroup 'DEAUDI005T\G-Audi-SwIntegration-Operators' `
    -WhatIf                     # drop -WhatIf to apply
```

It copies the engine, registers the counter, and **verifies** the console, the
gMSA, the group and WinRM first. It does **not** create accounts, grant SCCM
rights or open firewall ports — those stay with the teams that own them.

**Two files define the counter:**

| File | Role |
|---|---|
| `Endpoint\AudiSwIntegration.pssc` | The session — *who may connect* (`RoleDefinitions`) and *who does the work* (`GroupManagedServiceAccount`). Two independent settings. |
| `Endpoint\AudiSwIntegration.psrc` | The role — the **only** commands that exist for a caller. |

**On the file name question:** the `.pssc` is a *recipe read once at
registration*. Windows copies the settings into its own store, so afterwards the
file is not needed and may be deleted or renamed. What matters is:

- **the endpoint name** (`AudiSwIntegration`) — the client asks for it by name. It
  lives in the environment XML as `Service/@configurationName`, so changing it is
  a **config edit, not a code change**.
- **the install path** — the role capability points at the module folder. Keep it
  fixed and documented.

```powershell
Get-PSSessionConfiguration -Name AudiSwIntegration        # inspect
Set-PSSessionConfiguration -Name AudiSwIntegration ...    # change a setting
Unregister-PSSessionConfiguration -Name AudiSwIntegration -Force   # remove
```

### 3.3 Verify

```powershell
# from a packager PC, as a packager
Invoke-Command -ComputerName AUDIINSA1298 -ConfigurationName AudiSwIntegration -ScriptBlock { Get-AudiEnvironmentCode }

# must FAIL for someone outside the group
# must FAIL to escape:
Invoke-Command -ComputerName AUDIINSA1298 -ConfigurationName AudiSwIntegration -ScriptBlock { Get-ChildItem C:\ }
```

---

## 4. Extra for Option B — drop folder

### 4.1 The folder and its rights

```
\\<server>\SwIntegration-Inbox$\
    New\        packagers create job files here
    Working\    claimed by the watcher
    Done\       finished, with a .result.json beside it
    Failed\
```

| Principal | Share | NTFS | On which folder |
|---|---|---|---|
| Operator group | Change | **Create files / write data** only — *not* read, *not* delete | `New\` only |
| Service account | Full | Modify | all four |

Granting *create only* on `New\` means one packager cannot read, alter or delete
another's job.

**Very likely no new permission is needed.** Their existing flow already copies
content into the secure zone, so packagers have write access there today — this
may be a new folder beside one they already use.

### 4.2 How identity is proven — the part that needs care

With a live connection Windows states who called, and it cannot be faked. **A file
carries no such guarantee**: whoever can write to the folder could put any name
inside it.

So `Watch-AudiSwDropFolder.ps1` **ignores any requester written in the file** and
takes the **NTFS owner**, which Windows stamps at creation and the writer cannot
forge. That is what keeps the audit trail honest, and it is the single most
important detail in this option.

### 4.3 The scheduled task

```powershell
.\Install-AudiSwDropWatcher.ps1 `
    -Gmsa       'DEAUDI005T\svc-swintegration$' `
    -DropFolder '\\audiinsv1059\SwIntegration-Inbox$' `
    -WhatIf
```

Runs as the gMSA, so **no password is stored in Task Scheduler either**. Every few
minutes it claims jobs by moving them to `Working\` — which also prevents two runs
picking up the same job — and writes a `.result.json` back.

### 4.4 Answers for the security review

| Question | Answer |
|---|---|
| Is any port opened? | No. Nothing connects inward. |
| Can a packager run code on the server? | No. They write a data file. The watcher reads named fields only and never executes file content. |
| Can a packager impersonate another? | No. The requester is the NTFS file owner, not a field in the file. |
| Can a packager see others' jobs? | Not if `New\` grants create-only, as specified. |
| What if the watcher stops? | Jobs queue in `New\`. Nothing is lost. Monitor the task like any other. |

---

## 5. Side by side

| | Common | A — live | B — drop folder |
|---|---|---|---|
| Service account (gMSA) | ✔ | | |
| Operator group | ✔ | | |
| SCCM rights for the account | ✔ | | |
| Content share access for the account | ✔ | | |
| ARS rights for the account | ✔ | | |
| Engine installed on the server | ✔ | | |
| Firewall channel | | **required** | not needed |
| Endpoint registered | | **required** | — |
| Drop folder + rights | | — | **required** |
| Scheduled task | | — | **required** |
| Packager needs folder access | | no | **yes** |
| Work starts | | immediately | within a few minutes |
| Packager sees live progress | | **yes** | no |
| Who asked — proven by | | Windows, unfakeable | NTFS file owner |
| Survives a closed barrier | | no | **yes** |

---

## 6. Order of work

| # | Step | Owner |
|---|---|---|
| 1 | Decide option A or B | Audi + us |
| 2 | Confirm the PCZ values still marked `verified="false"` | Audi |
| 3 | Create the gMSA and the operator group | AD team |
| 4 | Install the gMSA on the server | Server team |
| 5 | Grant SCCM rights, share access and ARS rights to the account | SCCM / server / IAM |
| 6 | *(A)* firewall rule — *(B)* drop folder and its rights | Network / server team |
| 7 | Install the engine and register the endpoint or task | Us |
| 8 | Verify on **ICZ** with a real package | Us + Audi |
| 9 | Roll out to INA, then PCZ | Us + Audi |
| 10 | Withdraw the packagers' personal MECM admin accounts | Audi |

Step 10 is the point of the project — worth stating in the plan so it is not
forgotten once the tool works.

---

## 7. Acceptance test

On a PC with **no SCCM console**, signed in as an account with **no SCCM rights**:

1. Integrate a real test package on ICZ — it succeeds.
2. The application's **Owner** in SCCM reads the **service account**.
3. The log and `job.json` name the **real person** who asked.
4. Point the content share at a missing path — the tool reports the real reason
   and creates nothing.
5. Stop a run halfway — what it created is rolled back.
6. Remove someone from the operator group — their next attempt is refused.

Passing 1–3 proves the whole design: the shared account really does the work, and
the packager really no longer needs privileges.
