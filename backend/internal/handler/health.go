package handler

import (
	"context"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"
)

// Health returns an echo.HandlerFunc that pings the database pool.
// Returns 200 if healthy, 503 if the ping fails. When pool is nil
// (no-DB mode) it reports 200 so the Fly.io proxy doesn't kill the
// container before migrations finish.
func Health(pool *pgxpool.Pool) echo.HandlerFunc {
	return func(c echo.Context) error {
		if pool == nil {
			return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
		}

		ctx, cancel := context.WithTimeout(c.Request().Context(), 2*time.Second)
		defer cancel()
		if err := pool.Ping(ctx); err != nil {
			return c.JSON(http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
		}
		return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
	}
}
