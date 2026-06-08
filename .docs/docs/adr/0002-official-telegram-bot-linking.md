# Official Telegram Bot Linking

The Telegram gateway uses one official product bot and maps each Telegram sender to an internal user through a temporary `/start` code. This avoids requiring every user to create a BotFather bot, keeps bot credentials in the backend, and ensures the agent resolves context from the internal `user_id` rather than from the shared bot identity.
