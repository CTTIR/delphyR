CREATE TABLE research.protocol_amendments (
 id uuid PRIMARY KEY,
 study_id uuid NOT NULL,
 previous_protocol_id uuid NOT NULL,
 protocol_id uuid NOT NULL UNIQUE,
 actor_id uuid NOT NULL REFERENCES identity.principals,
 reason text NOT NULL CHECK(length(reason)>0),
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(study_id,previous_protocol_id) REFERENCES research.protocol_versions(study_id,id),
 FOREIGN KEY(study_id,protocol_id) REFERENCES research.protocol_versions(study_id,id),
 CHECK(previous_protocol_id<>protocol_id)
);
CREATE TRIGGER protocol_amendments_immutable BEFORE UPDATE OR DELETE ON research.protocol_amendments FOR EACH ROW EXECUTE FUNCTION ops.immutable();
