SELECT row_to_json(audit_requests) FROM audit_requests WHERE request_timestamp > '${BEGIN_REQUESTS}' AND request_timestamp < '${END_REQUESTS}';
