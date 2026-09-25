-- Synthetic-only communications: immutable approved envelopes, separate delivery state.
CREATE TABLE ops.campaigns(
 id uuid PRIMARY KEY, study_id uuid NOT NULL REFERENCES research.studies, round_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('invitation','round_start','reminder','deadline_change','completion')),
 locale text NOT NULL CHECK(locale IN ('de','en')), template_version integer NOT NULL CHECK(template_version>0),
 subject text NOT NULL CHECK(length(btrim(subject))>0), body text NOT NULL CHECK(length(btrim(body))>0),
 hash text NOT NULL, created_by uuid NOT NULL REFERENCES identity.principals,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(study_id,id), UNIQUE(study_id,round_id,id),
 FOREIGN KEY(study_id,round_id) REFERENCES research.rounds(study_id,id));
CREATE TABLE ops.campaign_recipients(
 study_id uuid NOT NULL, round_id uuid NOT NULL, campaign_id uuid NOT NULL, enrollment_id uuid NOT NULL,
 PRIMARY KEY(campaign_id,enrollment_id), UNIQUE(study_id,campaign_id,enrollment_id),
 FOREIGN KEY(study_id,round_id,campaign_id) REFERENCES ops.campaigns(study_id,round_id,id),
 FOREIGN KEY(study_id,round_id,enrollment_id) REFERENCES research.enrollments(study_id,round_id,id));
CREATE TABLE ops.campaign_releases(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, campaign_id uuid NOT NULL UNIQUE,
 approved_hash text NOT NULL, reason text NOT NULL CHECK(length(btrim(reason))>0),
 approved_by uuid NOT NULL REFERENCES identity.principals, approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(study_id,campaign_id) REFERENCES ops.campaigns(study_id,id));
CREATE TABLE ops.campaign_cancellations(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, campaign_id uuid NOT NULL UNIQUE,
 reason text NOT NULL CHECK(length(btrim(reason))>0), cancelled_by uuid NOT NULL REFERENCES identity.principals,
 cancelled_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(study_id,campaign_id) REFERENCES ops.campaigns(study_id,id));
CREATE TABLE ops.message_outbox(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, campaign_id uuid NOT NULL, enrollment_id uuid NOT NULL,
 dedupe_key text NOT NULL UNIQUE, created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(study_id,id),
 UNIQUE(campaign_id,enrollment_id),
 FOREIGN KEY(study_id,campaign_id,enrollment_id) REFERENCES ops.campaign_recipients(study_id,campaign_id,enrollment_id));
CREATE TABLE ops.message_delivery(
 message_id uuid PRIMARY KEY REFERENCES ops.message_outbox,
 state text NOT NULL DEFAULT 'queued' CHECK(state IN ('queued','running','sink_recorded','suppressed','delivery_unknown')),
 lease_token uuid, lease_until timestamptz, attempts integer NOT NULL DEFAULT 0,
 reason text, updated_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE TABLE ops.message_sink(
 message_id uuid PRIMARY KEY REFERENCES ops.message_outbox, campaign_hash text NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE INDEX message_delivery_queue ON ops.message_delivery(state,lease_until);
CREATE TRIGGER immutable_campaign BEFORE UPDATE OR DELETE ON ops.campaigns FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_campaign_recipient BEFORE UPDATE OR DELETE ON ops.campaign_recipients FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_campaign_release BEFORE UPDATE OR DELETE ON ops.campaign_releases FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_campaign_cancel BEFORE UPDATE OR DELETE ON ops.campaign_cancellations FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_message_outbox BEFORE UPDATE OR DELETE ON ops.message_outbox FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_message_sink BEFORE UPDATE OR DELETE ON ops.message_sink FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE FUNCTION ops.protect_campaign_recipient() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 PERFORM id FROM ops.campaigns WHERE id=NEW.campaign_id FOR SHARE;
 IF EXISTS(SELECT 1 FROM ops.campaign_releases WHERE campaign_id=NEW.campaign_id) THEN RAISE EXCEPTION 'campaign recipients released'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER campaign_recipients_locked BEFORE INSERT ON ops.campaign_recipients FOR EACH ROW EXECUTE FUNCTION ops.protect_campaign_recipient();
