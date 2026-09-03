package com.devincodes.vulntrack.api;

import com.devincodes.vulntrack.model.AppUser;
import com.devincodes.vulntrack.security.JwtUtil;
import jakarta.persistence.EntityManager;
import jakarta.persistence.NoResultException;
import jakarta.persistence.PersistenceContext;
import jakarta.transaction.Transactional;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.mindrot.jbcrypt.BCrypt;

@Path("/auth")
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class AuthResource {

    @PersistenceContext(unitName = "vulntrackPU")
    private EntityManager em;

    public static class Credentials {
        public String username;
        public String password;
        public String role; // only used on register
    }

    @POST
    @Path("/register")
    @Transactional
    public Response register(Credentials creds) {
        AppUser user = new AppUser();
        user.setUsername(creds.username);
        user.setPasswordHash(BCrypt.hashpw(creds.password, BCrypt.gensalt()));
        user.setRole(creds.role != null ? creds.role : "ANALYST");
        em.persist(user);
        return Response.status(Response.Status.CREATED).build();
    }

    @POST
    @Path("/login")
    public Response login(Credentials creds) {
        AppUser user;
        try {
            user = em.createQuery("SELECT u FROM AppUser u WHERE u.username = :username", AppUser.class)
                    .setParameter("username", creds.username)
                    .getSingleResult();
        } catch (NoResultException e) {
            return Response.status(Response.Status.UNAUTHORIZED).build();
        }

        if (!BCrypt.checkpw(creds.password, user.getPasswordHash())) {
            return Response.status(Response.Status.UNAUTHORIZED).build();
        }

        String token = JwtUtil.generateToken(user.getUsername(), user.getRole());
        return Response.ok("{\"token\":\"" + token + "\"}").build();
    }
}