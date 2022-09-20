SELECT row_to_json(audit_objects) FROM audit_objects WHERE ttl > '${BEGIN_OBJECTS}' AND ttl < '${END_OBJECTS}';
