package com.devincodes.vulntrack.api;

import com.devincodes.vulntrack.model.AppUser;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.List;

@Path("/users")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class AppUserResource {

    @PersistenceContext(unitName = "vulntrackPU")
    private EntityManager em;

    @GET
    public List<AppUser> getAll() {
        return em.createQuery("SELECT u FROM AppUser u", AppUser.class).getResultList();
    }

    @GET
    @Path("/{id}")
    public Response getOne(@PathParam("id") Long id) {
        AppUser u = em.find(AppUser.class, id);
        if (u == null) return Response.status(Response.Status.NOT_FOUND).build();
        return Response.ok(u).build();
    }

    @POST
    @Transactional
    public Response create(AppUser u) {
        em.persist(u);
        return Response.status(Response.Status.CREATED).entity(u).build();
    }

    @PUT
    @Path("/{id}")
    @Transactional
    public Response update(@PathParam("id") Long id, AppUser updated) {
        AppUser existing = em.find(AppUser.class, id);
        if (existing == null) return Response.status(Response.Status.NOT_FOUND).build();
        existing.setUsername(updated.getUsername());
        existing.setRole(updated.getRole());
        return Response.ok(existing).build();
    }

    @DELETE
    @Path("/{id}")
    @Transactional
    public Response delete(@PathParam("id") Long id) {
        AppUser existing = em.find(AppUser.class, id);
        if (existing == null) return Response.status(Response.Status.NOT_FOUND).build();
        em.remove(existing);
        return Response.noContent().build();
    }
}