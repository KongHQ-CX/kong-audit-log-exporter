package main

import (
	"fmt"
	"log"
	"os"
	"time"

	"github.com/KongHQ-CX/kong-admin-api-logger/internal/cmd"
)

func main() {
	// Set up
	kongAdminURL := os.Getenv("KONG_ADMIN_URL")
	if kongAdminURL == "" {
		log.Fatalf("KONG_ADMIN_URL not set in env")
	}

	kongAdminToken := os.Getenv("KONG_ADMIN_TOKEN")
	if kongAdminToken == "" {
		log.Fatalf("KONG_ADMIN_TOKEN not set in env")
	}

	storageNamespace := os.Getenv("STORAGE_NAMESPACE")
	if storageNamespace == "" {
		storageNamespace = "apiplatform-cp"
	}

	runIntervalSecondsString := os.Getenv("RUN_INTERVAL_SECONDS")
	if runIntervalSecondsString == "" {
		runIntervalSecondsString = "10"
	}

	for {
		cmd.Cmd(kongAdminURL, kongAdminToken, storageNamespace)
		elapse, _ := time.ParseDuration(fmt.Sprintf("%ss", runIntervalSecondsString))
		time.Sleep(elapse)
	}
}
