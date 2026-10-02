-- Operational state: worker heartbeats and the end of an export's life.
CREATE TABLE ops.worker_heartbeats(
 worker_id text PRIMARY KEY CHECK(worker_id ~ '^[A-Za-z0-9_.:-]{1,100}$'),
 started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 last_seen_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 software_version text NOT NULL CHECK(length(software_version) BETWEEN 1 AND 100));
-- An export is a temporary private copy. After its download period its files
-- are removed; the registration stays and records when that happened.
ALTER TABLE ops.artifacts ADD COLUMN created_at timestamptz;
ALTER TABLE ops.artifacts ALTER COLUMN created_at SET DEFAULT clock_timestamp();
ALTER TABLE ops.artifacts ADD COLUMN removed_at timestamptz;
CREATE FUNCTION ops.protect_artifact() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'immutable record'; END IF;
 IF (NEW.id,NEW.study_id,NEW.actor_id,NEW.snapshot_id,NEW.storage_key,NEW.checksum,NEW.expires_at,NEW.profile,NEW.created_at)
    IS DISTINCT FROM (OLD.id,OLD.study_id,OLD.actor_id,OLD.snapshot_id,OLD.storage_key,OLD.checksum,OLD.expires_at,OLD.profile,OLD.created_at)
    OR OLD.removed_at IS NOT NULL OR NEW.removed_at IS NULL OR OLD.expires_at>clock_timestamp() THEN
  RAISE EXCEPTION 'immutable record';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER artifact_guard BEFORE UPDATE OR DELETE ON ops.artifacts FOR EACH ROW EXECUTE FUNCTION ops.protect_artifact();
