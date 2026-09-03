package com.devincodes.vulntrack.security;

import jakarta.annotation.Priority;
import jakarta.ws.rs.Priorities;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import jakarta.inject.Inject;

import java.io.IOException;

@Provider
@Priority(Priorities.AUTHENTICATION)
public class AuthFilter implements ContainerRequestFilter {

    @Inject
    private RequestUserContext userContext;

    @Override
    public void filter(ContainerRequestContext ctx) throws IOException {
        String path = ctx.getUriInfo().getPath();

        // Let login/register through without a token
        if (path.startsWith("auth/") || path.startsWith("/auth/")) {
            return;
        }

        String authHeader = ctx.getHeaderString("Authorization");
        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            ctx.abortWith(Response.status(Response.Status.UNAUTHORIZED)
                    .entity("Missing or invalid Authorization header").build());
            return;
        }

        String token = authHeader.substring("Bearer ".length());
        try {
            Claims claims = JwtUtil.parseToken(token);
            userContext.setUsername(claims.getSubject());
            userContext.setRole(claims.get("role", String.class));
        } catch (JwtException e) {
            ctx.abortWith(Response.status(Response.Status.UNAUTHORIZED)
                    .entity("Invalid or expired token").build());
        }
    }
}