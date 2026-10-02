-- The approved send window of a campaign. Campaigns approved before this
-- migration have no window and remain immediately eligible.
CREATE TABLE ops.campaign_schedules(
 campaign_id uuid PRIMARY KEY, study_id uuid NOT NULL,
 not_before timestamptz NOT NULL, quiet_start time, quiet_end time, timezone text NOT NULL,
 CHECK((quiet_start IS NULL)=(quiet_end IS NULL)), CHECK(quiet_start IS NULL OR quiet_start<>quiet_end),
 FOREIGN KEY(study_id,campaign_id) REFERENCES ops.campaigns(study_id,id));
CREATE TRIGGER immutable_campaign_schedule BEFORE UPDATE OR DELETE ON ops.campaign_schedules FOR EACH ROW EXECUTE FUNCTION ops.immutable();
-- Outcomes of a provider adapter, a retry time, and the human resolution of
-- an uncertain delivery. An uncertain delivery is never resent automatically.
ALTER TABLE ops.message_delivery DROP CONSTRAINT message_delivery_state_check;
ALTER TABLE ops.message_delivery ADD CONSTRAINT message_delivery_state_check CHECK(state IN ('queued','running','sink_recorded','accepted','suppressed','delivery_unknown','failed','resolved_delivered','abandoned'));
ALTER TABLE ops.message_delivery ADD COLUMN available_at timestamptz NOT NULL DEFAULT clock_timestamp();
ALTER TABLE ops.message_delivery ADD COLUMN adapter text;
ALTER TABLE ops.message_delivery ADD COLUMN provider_ref text;
CREATE TABLE ops.delivery_resolutions(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, message_id uuid NOT NULL,
 resolution text NOT NULL CHECK(resolution IN ('confirmed_delivered','requeue','abandon')),
 reason text NOT NULL CHECK(length(btrim(reason))>0),
 actor_id uuid NOT NULL REFERENCES identity.principals, recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(study_id,message_id) REFERENCES ops.message_outbox(study_id,id));
CREATE TRIGGER immutable_delivery_resolution BEFORE UPDATE OR DELETE ON ops.delivery_resolutions FOR EACH ROW EXECUTE FUNCTION ops.immutable();
