package model

import "encoding/json"

type AuditData struct {
	Next   *string           `json:"next"`
	Offset *string           `json:"offset"`
	Data   []json.RawMessage `json:"data"`
}
