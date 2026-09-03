package com.devincodes.vulntrack.api;

import java.time.LocalDate;

public class FindingInput {
    public Long assetId;
    public Long vulnerabilityId;
    public Long assignedUserId;
    public String status;
    public LocalDate remediationDeadline;
}