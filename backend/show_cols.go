package main
import (
	"context"
	"fmt"
	"os"
	"github.com/jackc/pgx/v5"
)
func main() {
	conn, _ := pgx.Connect(context.Background(), os.Getenv("DATABASE_URL"))
	defer conn.Close(context.Background())
	rows, _ := conn.Query(context.Background(), "SELECT column_name FROM information_schema.columns WHERE table_name = 'notes'")
	defer rows.Close()
	for rows.Next() {
		var col string
		rows.Scan(&col)
		fmt.Println(col)
	}
}
