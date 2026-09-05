package com.devincodes.vulntrack.api;

import com.devincodes.vulntrack.model.*;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.List;

@Path("/findings")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class FindingResource {

    @PersistenceContext(unitName = "vulntrackPU")
    private EntityManager em;

    @GET
    public List<Finding> getAll() {
        return em.createQuery("SELECT f FROM Finding f", Finding.class).getResultList();
    }

    @GET
    @Path("/{id}")
    public Response getOne(@PathParam("id") Long id) {
        Finding f = em.find(Finding.class, id);
        if (f == null) return Response.status(Response.Status.NOT_FOUND).build();
        return Response.ok(f).build();
    }

    @POST
    @Transactional
    public Response create(FindingInput input) {
        Asset asset = em.find(Asset.class, input.assetId);
        Vulnerability vuln = em.find(Vulnerability.class, input.vulnerabilityId);
        if (asset == null || vuln == null) {
            return Response.status(Response.Status.BAD_REQUEST)
                    .entity("assetId or vulnerabilityId does not exist").build();
        }
        AppUser user = input.assignedUserId != null ? em.find(AppUser.class, input.assignedUserId) : null;

        Finding f = new Finding();
        f.setAsset(asset);
        f.setVulnerability(vuln);
        f.setAssignedUser(user);
        f.setStatus(input.status);
        f.setRemediationDeadline(input.remediationDeadline != null ?    java.time.LocalDate.parse(input.remediationDeadline) : null);
        em.persist(f);
        return Response.status(Response.Status.CREATED).entity(f).build();
    }

    @PUT
    @Path("/{id}")
    @Transactional
    public Response update(@PathParam("id") Long id, FindingInput input) {
        Finding existing = em.find(Finding.class, id);
        if (existing == null) return Response.status(Response.Status.NOT_FOUND).build();

        if (input.assetId != null) existing.setAsset(em.find(Asset.class, input.assetId));
        if (input.vulnerabilityId != null) existing.setVulnerability(em.find(Vulnerability.class, input.vulnerabilityId));
        if (input.assignedUserId != null) existing.setAssignedUser(em.find(AppUser.class, input.assignedUserId));
        if (input.status != null) existing.setStatus(input.status);
        if (input.remediationDeadline != null) existing.setRemediationDeadline(java.time.LocalDate.parse(input.remediationDeadline));

        return Response.ok(existing).build();
    }

    @DELETE
    @Path("/{id}")
    @Transactional
    public Response delete(@PathParam("id") Long id) {
        Finding existing = em.find(Finding.class, id);
        if (existing == null) return Response.status(Response.Status.NOT_FOUND).build();
        em.remove(existing);
        return Response.noContent().build();
    }
}