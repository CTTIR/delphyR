CREATE TABLE research.participation_withdrawals (
 id uuid PRIMARY KEY,
 study_id uuid NOT NULL,
 panelist_id uuid NOT NULL,
 actor_id uuid NOT NULL REFERENCES identity.principals,
 retention_policy text NOT NULL CHECK(retention_policy='synthetic_retain_prior_data'),
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(study_id,panelist_id),
 FOREIGN KEY(study_id,panelist_id) REFERENCES research.panelists(study_id,id)
);
CREATE TRIGGER participation_withdrawals_immutable BEFORE UPDATE OR DELETE ON research.participation_withdrawals FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TABLE research.panel_group_events (
 id uuid PRIMARY KEY,
 study_id uuid NOT NULL,
 panelist_id uuid NOT NULL,
 actor_id uuid NOT NULL REFERENCES identity.principals,
 previous_group text NOT NULL,
 group_code text NOT NULL,
 reason text NOT NULL CHECK(length(reason)>0),
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(study_id,panelist_id) REFERENCES research.panelists(study_id,id),
 CHECK(previous_group<>group_code)
);
CREATE TRIGGER panel_group_events_immutable BEFORE UPDATE OR DELETE ON research.panel_group_events FOR EACH ROW EXECUTE FUNCTION ops.immutable();
