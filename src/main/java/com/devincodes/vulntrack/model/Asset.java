package com.devincodes.vulntrack.model;

import jakarta.persistence.*;

@Entity
@Table(name = "asset")
public class Asset {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String hostname;

    @Column(name = "ip_address")
    private String ipAddress;

    @Column(name = "asset_type")
    private String assetType;

    private String owner;

    public Asset() {}

    public Long getId() { return id; }
    public String getHostname() { return hostname; }
    public void setHostname(String hostname) { this.hostname = hostname; }
    public String getIpAddress() { return ipAddress; }
    public void setIpAddress(String ipAddress) { this.ipAddress = ipAddress; }
    public String getAssetType() { return assetType; }
    public void setAssetType(String assetType) { this.assetType = assetType; }
    public String getOwner() { return owner; }
    public void setOwner(String owner) { this.owner = owner; }
}