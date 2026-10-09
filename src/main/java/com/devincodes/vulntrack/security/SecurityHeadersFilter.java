package com.devincodes.vulntrack.security;

import jakarta.servlet.*;
import jakarta.servlet.annotation.WebFilter;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

/**
 * Sets security response headers on every response.
 *
 * Added in Phase 8 after a ZAP baseline scan reported four missing headers.
 * script-src is 'self' with no 'unsafe-inline', which is only possible
 * because the app's JavaScript was moved out of index.html into app.js
 * first. A CSP that permits inline script does not meaningfully defend
 * against XSS - it only quiets the scanner.
 *
 * style-src keeps 'unsafe-inline' deliberately: CSS injection is a far
 * weaker primitive than script injection.
 */
@WebFilter("/*")
public class SecurityHeadersFilter implements Filter {

    private static final String CSP = String.join("; ",
        "default-src 'self'",
        "script-src 'self'",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src https://fonts.gstatic.com",
        "img-src 'self' data:",
        "connect-src 'self'",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "object-src 'none'");

    @Override
    public void doFilter(ServletRequest req, ServletResponse res, FilterChain chain)
            throws IOException, ServletException {
        HttpServletResponse http = (HttpServletResponse) res;
        http.setHeader("Content-Security-Policy", CSP);
        http.setHeader("X-Content-Type-Options", "nosniff");
        http.setHeader("X-Frame-Options", "DENY");
        http.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
        http.setHeader("Permissions-Policy",
            "geolocation=(), camera=(), microphone=(), payment=(), usb=()");
        if (req.isSecure()) {
            http.setHeader("Strict-Transport-Security",
                "max-age=31536000; includeSubDomains");
        }
        chain.doFilter(req, res);
    }
}
