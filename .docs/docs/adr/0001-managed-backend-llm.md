# Managed Backend LLM

The product uses LLM keys managed by the backend rather than asking each user to provide their own key. This keeps onboarding simple, lets the backend choose models per task type, enables centralized prompt caching and usage tracking, and avoids exposing provider credentials to clients.
