package com.devincodes.vulntrack.model;

import jakarta.persistence.*;
import java.time.LocalDate;

@Entity
@Table(name = "finding")
public class Finding {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false)
    @JoinColumn(name = "asset_id")
    private Asset asset;

    @ManyToOne(optional = false)
    @JoinColumn(name = "vulnerability_id")
    private Vulnerability vulnerability;

    @ManyToOne
    @JoinColumn(name = "assigned_user_id")
    private AppUser assignedUser;

    @Column(nullable = false)
    private String status;

    @Column(name = "remediation_deadline")
    private LocalDate remediationDeadline;

    public Finding() {}

    public Long getId() { return id; }
    public Asset getAsset() { return asset; }
    public void setAsset(Asset asset) { this.asset = asset; }
    public Vulnerability getVulnerability() { return vulnerability; }
    public void setVulnerability(Vulnerability vulnerability) { this.vulnerability = vulnerability; }
    public AppUser getAssignedUser() { return assignedUser; }
    public void setAssignedUser(AppUser assignedUser) { this.assignedUser = assignedUser; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public LocalDate getRemediationDeadline() { return remediationDeadline; }
    public void setRemediationDeadline(LocalDate deadline) { this.remediationDeadline = deadline; }
}