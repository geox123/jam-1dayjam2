# Shared online leaderboard

Airebound uses Supabase for the shared arcade leaderboard.

1. Create a Supabase project and enable Anonymous Sign-Ins.
2. Run `migrations/001_leaderboard.sql` in the SQL editor.
3. Create and deploy the `leaderboard` Edge Function from `functions/leaderboard`.
4. Put the project URL and publishable key in `leaderboard_config.gd`.
5. Re-export the Web build.

Only the publishable key belongs in the game. The service-role key is used only by the Edge Function and must remain a Supabase secret.

The game submits a player-chosen name, score, and Run duration. The function authenticates the anonymous session, applies basic bounds, and stores only the top-ten query fields needed by the game.

The production deployment is triggered from the repository's `main` branch through the Supabase GitHub integration.
