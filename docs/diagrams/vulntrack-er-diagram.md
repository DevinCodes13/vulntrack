# VulnTrack — entity relationship diagram

Core data model: an `Asset` can have many `Finding`s, each linking a specific
`Vulnerability` to that asset, optionally assigned to a `User` for remediation.

```mermaid
erDiagram
  ASSET ||--o{ FINDING : has
  VULNERABILITY ||--o{ FINDING : "identified in"
  USER ||--o{ FINDING : "assigned to"
  ASSET {
    long id PK
    string hostname
    string ipAddress
    string assetType
    string owner
  }
  VULNERABILITY {
    long id PK
    string cveId
    string description
    string severity
    float cvssScore
  }
  FINDING {
    long id PK
    long assetId FK
    long vulnerabilityId FK
    long assignedUserId FK
    string status
    date remediationDeadline
  }
  USER {
    long id PK
    string username
    string role
  }
```

## Notes

- `Finding.assignedUserId` is nullable — a finding can exist before anyone is
  assigned to remediate it. Enforced at the JPA level (`@ManyToOne` without
  `optional = false`), not at the database schema level.
- The `USER` entity is implemented as `AppUser` in code (`AppUser.java`),
  since `USER` is a reserved word in some SQL dialects and breaks table
  creation if used literally.
