-- Audit events carry the recorded rationale and a short non-sensitive detail,
-- such as a target state. Earlier events keep their separate reason records.
ALTER TABLE ops.audit ADD COLUMN reason text;
ALTER TABLE ops.audit ADD COLUMN detail text;
-- Author-supplied documentation for reports. Each change is a new version.
CREATE TABLE research.study_documentation(
 id uuid PRIMARY KEY, study_id uuid NOT NULL REFERENCES research.studies,
 version integer NOT NULL CHECK(version>0), content jsonb NOT NULL, hash text NOT NULL,
 actor_id uuid NOT NULL REFERENCES identity.principals, reason text NOT NULL CHECK(length(btrim(reason))>0),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(study_id,version), UNIQUE(study_id,id));
CREATE TRIGGER immutable_study_documentation BEFORE UPDATE OR DELETE ON research.study_documentation FOR EACH ROW EXECUTE FUNCTION ops.immutable();
-- Human decisions on whether two versions of an item may be compared directly.
-- The most recent decision for a version pair is effective; history is kept.
CREATE TABLE research.item_comparability(
 id uuid PRIMARY KEY, study_id uuid NOT NULL REFERENCES research.studies,
 item_code text NOT NULL, dimension_code text NOT NULL,
 previous_version integer NOT NULL CHECK(previous_version>0), current_version integer NOT NULL CHECK(current_version>0),
 comparable boolean NOT NULL, reason text NOT NULL CHECK(length(btrim(reason))>0),
 actor_id uuid NOT NULL REFERENCES identity.principals, recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(previous_version<>current_version));
CREATE INDEX item_comparability_pair ON research.item_comparability(study_id,item_code,dimension_code,previous_version,current_version,recorded_at);
CREATE TRIGGER immutable_item_comparability BEFORE UPDATE OR DELETE ON research.item_comparability FOR EACH ROW EXECUTE FUNCTION ops.immutable();
-- Export profiles. A finished export no longer blocks a later request for
-- the same input; one analysis per requester and snapshot stays the rule.
ALTER TABLE ops.jobs ADD COLUMN profile text NOT NULL DEFAULT 'research_round';
UPDATE ops.jobs SET profile='analysis' WHERE type='analysis';
ALTER TABLE ops.jobs ADD CONSTRAINT jobs_profile_check CHECK((type='analysis' AND profile='analysis') OR (type='export' AND profile IN ('research_round','research_pseudonymized','study_summary','audit_restricted','contacts_restricted')));
ALTER TABLE ops.jobs DROP CONSTRAINT jobs_study_id_actor_id_type_input_id_key;
CREATE UNIQUE INDEX jobs_one_analysis ON ops.jobs(study_id,actor_id,input_id) WHERE type='analysis' AND state<>'dead_letter';
CREATE UNIQUE INDEX jobs_one_active_export ON ops.jobs(study_id,actor_id,input_id,profile) WHERE type='export' AND state IN ('queued','running','retry_wait');
ALTER TABLE ops.artifacts ADD COLUMN profile text NOT NULL DEFAULT 'research_round';
ALTER TABLE ops.artifacts ALTER COLUMN snapshot_id DROP NOT NULL;
ALTER TABLE ops.artifacts ADD CONSTRAINT artifacts_profile_check CHECK(profile IN ('research_round','research_pseudonymized','study_summary','audit_restricted','contacts_restricted') AND ((profile='research_round') = (snapshot_id IS NOT NULL)));
