ALTER TABLE research.snapshots ADD CONSTRAINT snapshots_round_identity UNIQUE(study_id,round_id,id);
CREATE TABLE research.snapshot_entries (
 study_id uuid NOT NULL,
 round_id uuid NOT NULL,
 snapshot_id uuid NOT NULL,
 enrollment_id uuid NOT NULL,
 submission_id uuid NOT NULL,
 response_revision_id uuid NOT NULL,
 PRIMARY KEY(snapshot_id,response_revision_id),
 FOREIGN KEY(study_id,round_id,snapshot_id) REFERENCES research.snapshots(study_id,round_id,id),
 FOREIGN KEY(study_id,round_id,enrollment_id,submission_id) REFERENCES research.submissions(study_id,round_id,enrollment_id,id),
 FOREIGN KEY(study_id,round_id,enrollment_id,response_revision_id) REFERENCES research.response_revisions(study_id,round_id,enrollment_id,id)
);
INSERT INTO research.snapshot_entries
 SELECT s.study_id,s.round_id,s.id,se.enrollment_id,se.submission_id,se.response_revision_id
 FROM research.snapshots s JOIN research.submission_entries se ON se.study_id=s.study_id AND se.round_id=s.round_id;
CREATE TRIGGER snapshot_entries_immutable BEFORE UPDATE OR DELETE ON research.snapshot_entries FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TABLE research.round_events (
 id uuid PRIMARY KEY,
 study_id uuid NOT NULL,
 round_id uuid NOT NULL,
 target_state text NOT NULL,
 content_hash text NOT NULL,
 actor_id uuid NOT NULL REFERENCES identity.principals,
 reason text NOT NULL CHECK(length(reason)>0),
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(study_id,round_id) REFERENCES research.rounds(study_id,id)
);
CREATE TRIGGER round_events_immutable BEFORE UPDATE OR DELETE ON research.round_events FOR EACH ROW EXECUTE FUNCTION ops.immutable();
