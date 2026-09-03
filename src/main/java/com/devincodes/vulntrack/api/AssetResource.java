package com.devincodes.vulntrack.api;

import jakarta.inject.Inject;
import com.devincodes.vulntrack.security.RequestUserContext;
import com.devincodes.vulntrack.model.Asset;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.List;

@Path("/assets")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class AssetResource {

    @PersistenceContext(unitName = "vulntrackPU")
    private EntityManager em;

    @Inject
    private RequestUserContext requestContext;

    @GET
    public List<Asset> getAll() {
        return em.createQuery("SELECT a FROM Asset a", Asset.class).getResultList();
    }

    @GET
    @Path("/{id}")
    public Response getOne(@PathParam("id") Long id) {
        Asset asset = em.find(Asset.class, id);
        if (asset == null) return Response.status(Response.Status.NOT_FOUND).build();
        return Response.ok(asset).build();
    }

    @POST
    @Transactional
    public Response create(Asset asset) {
        em.persist(asset);
        return Response.status(Response.Status.CREATED).entity(asset).build();
    }

    @PUT
    @Path("/{id}")
    @Transactional
    public Response update(@PathParam("id") Long id, Asset updated) {
        Asset existing = em.find(Asset.class, id);
        if (existing == null) return Response.status(Response.Status.NOT_FOUND).build();
        existing.setHostname(updated.getHostname());
        existing.setIpAddress(updated.getIpAddress());
        existing.setAssetType(updated.getAssetType());
        existing.setOwner(updated.getOwner());
        return Response.ok(existing).build();
    }

    @DELETE
    @Path("/{id}")
    @Transactional
    public Response delete(@PathParam("id") Long id) {
        String role = requestContext.getRole();
        if (!"ADMIN".equals(role)) {
            return Response.status(Response.Status.FORBIDDEN).build();
        }
        Asset existing = em.find(Asset.class, id);
        if (existing == null) return Response.status(Response.Status.NOT_FOUND).build();
        em.remove(existing);
        return Response.noContent().build();
    }
}