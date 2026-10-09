package com.devincodes.vulntrack.api;

import com.devincodes.vulntrack.model.AppUser;
import com.devincodes.vulntrack.security.RequestUserContext;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

import java.util.List;

/**
 * Phase 8 added the authorization checks below. Previously every method here
 * was reachable by any authenticated user, which allowed an ANALYST to read
 * all accounts and PUT their own record with role=ADMIN - anonymous to full
 * administrator in three requests, since registration is open.
 */
@Path("/users")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class AppUserResource {

    @PersistenceContext(unitName = "vulntrackPU")
    private EntityManager em;

    @Inject
    private RequestUserContext requestContext;

    private boolean isAdmin() {
        return "ADMIN".equals(requestContext.getRole());
    }

    private boolean isSelf(AppUser u) {
        return u != null && u.getUsername() != null
            && u.getUsername().equals(requestContext.getUsername());
    }

    private static Response forbidden() {
        return Response.status(Response.Status.FORBIDDEN).build();
    }

    @GET
    public Response getAll() {
        if (!isAdmin()) return forbidden();
        List<AppUser> users =
            em.createQuery("SELECT u FROM AppUser u", AppUser.class).getResultList();
        return Response.ok(users).build();
    }

    @GET
    @Path("/{id}")
    public Response getOne(@PathParam("id") Long id) {
        AppUser u = em.find(AppUser.class, id);
        if (u == null) return Response.status(Response.Status.NOT_FOUND).build();
        if (!isAdmin() && !isSelf(u)) return forbidden();
        return Response.ok(u).build();
    }

    @POST
    @Transactional
    public Response create(AppUser u) {
        if (!isAdmin()) return forbidden();
        em.persist(u);
        return Response.status(Response.Status.CREATED).entity(u).build();
    }

    @PUT
    @Path("/{id}")
    @Transactional
    public Response update(@PathParam("id") Long id, AppUser updated) {
        AppUser existing = em.find(AppUser.class, id);
        if (existing == null) return Response.status(Response.Status.NOT_FOUND).build();
        if (!isAdmin() && !isSelf(existing)) return forbidden();

        // A role change is an administrative action, never a self-service one.
        if (updated.getRole() != null && !updated.getRole().equals(existing.getRole())) {
            if (!isAdmin()) return forbidden();
            existing.setRole(updated.getRole());
        }
        if (updated.getUsername() != null) {
            existing.setUsername(updated.getUsername());
        }
        return Response.ok(existing).build();
    }

    @DELETE
    @Path("/{id}")
    @Transactional
    public Response delete(@PathParam("id") Long id) {
        if (!isAdmin()) return forbidden();
        AppUser existing = em.find(AppUser.class, id);
        if (existing == null) return Response.status(Response.Status.NOT_FOUND).build();
        em.remove(existing);
        return Response.noContent().build();
    }
}
