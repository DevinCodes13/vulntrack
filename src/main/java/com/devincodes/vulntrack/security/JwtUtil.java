package com.devincodes.vulntrack.security;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

import javax.crypto.SecretKey;
import java.util.Date;

public class JwtUtil {

    // NOTE: hardcoded for development only. In Phase 4 this moves to
    // AWS Secrets Manager / an environment variable, not source code.
    private static final SecretKey KEY = Keys.hmacShaKeyFor(
            "dev-only-secret-key-change-this-before-any-real-deployment!".getBytes());

    private static final long EXPIRATION_MS = 1000 * 60 * 60; // 1 hour

    public static String generateToken(String username, String role) {
        return Jwts.builder()
                .subject(username)
                .claim("role", role)
                .issuedAt(new Date())
                .expiration(new Date(System.currentTimeMillis() + EXPIRATION_MS))
                .signWith(KEY)
                .compact();
    }

    public static io.jsonwebtoken.Claims parseToken(String token) {
        return Jwts.parser()
                .verifyWith(KEY)
                .build()
                .parseSignedClaims(token)
                .getPayload();
    }
}