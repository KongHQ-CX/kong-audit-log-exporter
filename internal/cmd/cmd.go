package cmd

import (
	b64 "encoding/base64"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"time"

	"github.com/KongHQ-CX/kong-admin-api-logger/internal/kube"
	"github.com/KongHQ-CX/kong-admin-api-logger/internal/model"
)

func Cmd(kongAdminURL, kongAdminToken, storageNamespace string) {
	initialOffset := "0"
	var objectOffset *string = &initialOffset
	var requestOffset *string = &initialOffset

	// Optionally load cache of all admin IDs and usernames

	// Optionally load cache of all workspace IDs and names

	// Read the previous offset from Kubernetes Secrets
	storageSecret, err := kube.GetSecretExternal("audit-logger-tracking", storageNamespace)
	if err != nil {
		log.Fatalf("Could not read storage secret: %s", err)
	}

	if storageSecret != nil {
		objectOffsetString := string((*storageSecret)["OBJECT_OFFSET"])
		objectOffset = &objectOffsetString

		requestOffsetString := string((*storageSecret)["REQUEST_OFFSET"])
		requestOffset = &requestOffsetString

		fmt.Printf("Resuming from: | offset: %s | request: %s\n", *objectOffset, *requestOffset)
	} else {
		fmt.Println("Storage secret is empty - starting audit dump from 0")
	}

	// If the Secret does not exist then create it with value 0

	objectOffset = ExecuteEndpoint(kongAdminURL, kongAdminToken, "/audit/objects", objectOffset)
	requestOffset = ExecuteEndpoint(kongAdminURL, kongAdminToken, "/audit/requests", requestOffset)

	// Only apply any offset that has changed
	if objectOffset == nil && requestOffset == nil {
		// nothing
	} else if objectOffset == nil {
		kube.CreateSecretExternal(map[string][]byte{
			"REQUEST_OFFSET": []byte(*requestOffset),
		}, "audit-logger-tracking", storageNamespace)
	} else if requestOffset == nil {
		kube.CreateSecretExternal(map[string][]byte{
			"REQUEST_OFFSET": []byte(*requestOffset),
		}, "audit-logger-tracking", storageNamespace)
	} else {
		kube.CreateSecretExternal(map[string][]byte{
			"OBJECT_OFFSET":  []byte(*objectOffset),
			"REQUEST_OFFSET": []byte(*requestOffset),
		}, "audit-logger-tracking", storageNamespace)
	}
}

func ExecuteEndpoint(kongAdminURL, kongAdminToken, endpoint string, offset *string) *string {
	firstOffset := "0"

	var url string

	tr := &http.Transport{
		MaxIdleConns:       10,
		IdleConnTimeout:    30 * time.Second,
		DisableCompression: false,
	}
	client := &http.Client{Transport: tr}

	for {
		if *offset == firstOffset {
			url = fmt.Sprintf("%s%s", kongAdminURL, endpoint)
		} else {
			url = fmt.Sprintf("%s%s?offset=%s", kongAdminURL, endpoint, *offset)
		}

		req, _ := http.NewRequest("GET", url, nil)
		req.Header.Set("Kong-Admin-Token", kongAdminToken)
		resp, err := client.Do(req)

		if err != nil {
			log.Fatalf("could not make http request for offset %s: %s\n", *offset, err)
		}

		if resp.StatusCode > 200 {
			log.Fatalf("could not read response body for offset %s: non-200 status code (%s)\n", *offset, resp.Status)
		}

		body, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			log.Fatalf("could not read response body for offset 0: %s\n", err)
		}

		auditData := &model.AuditData{}
		json.Unmarshal(body, auditData)

		if len(auditData.Data) < 1 {
			// Do nothing
			return nil
		}

		// if auditData.Offset != nil {
		// 	fmt.Println(*auditData.Offset)
		// }
		for _, v := range auditData.Data {
			fmt.Printf("%s\n", v)
		}

		if auditData.Offset == nil {
			// Get the ID of the last record in the last results
			record := auditData.Data[len(auditData.Data)-1]
			recordStruct := model.PartialAuditEntry{}
			json.Unmarshal([]byte(record), &recordStruct)

			var offsetID string
			if recordStruct.ID != nil {
				offsetID = *recordStruct.ID
			} else {
				offsetID = *recordStruct.RequestID
			}

			// Base64 it in format ["id"]
			newOffset := b64.RawStdEncoding.EncodeToString([]byte(fmt.Sprintf(`["%s"]`, offsetID)))

			// Return
			return &newOffset
		} else {
			// Continue in loop
			offset = auditData.Offset
		}
	}
}
