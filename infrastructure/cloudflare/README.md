# Cloudflare deployment (dashboard-managed)

Use a self-hosted Access application for chat.example.com (replace with your domain privately), with no path restriction. Attach an Allow policy containing only explicitly authorized email addresses such as user@example.com (placeholder). Select One-time PIN or an explicitly configured OAuth identity provider. Do not use Bypass or Everyone.

Install cloudflared with the repository script; create or select YOUR_TUNNEL_NAME in the dashboard. Run the dashboard-provided service install command privately; never store the token here. Add a Published application route (not private CIDR/hostname routing) with HTTP origin 127.0.0.1:8080. Enable Protect with Access and set the correct team and application audience for origin JWT validation before publishing. Check that no alternate unprotected routes exist.

For Google OAuth, use the actual team domain in place of YOUR_TEAM.cloudflareaccess.com. Store OAuth client credentials only in the appropriate provider dashboards.

Test unauthenticated requests to /health and /v1/models (must redirect to login or deny access; no inference data). Verify authorized browser login, chat completion, and access from an external network. Reboot and check both services. Remove public routing before deleting Access configuration.

OTP delivery was unresolved during the original deployment. See the manual for policy tester behavior, email suppression and Google OAuth alternatives. Do not consider this production ready until login and access tests pass. Authorized users share the full reachable llama.cpp API; no per-user quotas or isolated server-side history are implemented.
