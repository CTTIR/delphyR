-- Explicit stable-account approvals and single-use synthetic invitation claims.
CREATE TABLE identity.panel_invitations(
 id uuid PRIMARY KEY, study_id uuid NOT NULL, draft_id uuid NOT NULL,
 expected_principal_id uuid NOT NULL REFERENCES identity.principals,
 expected_issuer text NOT NULL, expected_subject text NOT NULL,
 token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[0-9a-f]{64}$'),
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 actor_id uuid NOT NULL REFERENCES identity.principals, reason text NOT NULL CHECK(length(btrim(reason))>0),
 UNIQUE(study_id,id), UNIQUE(study_id,id,draft_id,expected_principal_id),
 CHECK(expires_at>created_at AND expires_at<=created_at+interval '24 hours'),
 FOREIGN KEY(study_id,draft_id) REFERENCES identity.panel_invitation_drafts(study_id,id));
CREATE TABLE identity.panel_invitation_revocations(
 invitation_id uuid PRIMARY KEY, study_id uuid NOT NULL,
 actor_id uuid NOT NULL REFERENCES identity.principals,
 reason text NOT NULL CHECK(length(btrim(reason))>0), recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(study_id,invitation_id) REFERENCES identity.panel_invitations(study_id,id));
CREATE TABLE identity.panel_invitation_acceptances(
 invitation_id uuid PRIMARY KEY, study_id uuid NOT NULL, draft_id uuid NOT NULL,
 principal_id uuid NOT NULL REFERENCES identity.principals,
 membership_id uuid NOT NULL, panelist_id uuid NOT NULL,
 command_key text NOT NULL, payload_hash text NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(study_id,draft_id), UNIQUE(study_id,principal_id), UNIQUE(study_id,principal_id,command_key),
 FOREIGN KEY(study_id,invitation_id,draft_id,principal_id)
   REFERENCES identity.panel_invitations(study_id,id,draft_id,expected_principal_id),
 FOREIGN KEY(study_id,membership_id) REFERENCES identity.memberships(study_id,id),
 FOREIGN KEY(study_id,panelist_id) REFERENCES research.panelists(study_id,id));
CREATE FUNCTION ops.guard_invitation_acceptance() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE inv identity.panel_invitations; BEGIN
 SELECT * INTO inv FROM identity.panel_invitations WHERE id=NEW.invitation_id AND study_id=NEW.study_id FOR UPDATE;
 IF NOT FOUND OR inv.expires_at<=clock_timestamp() OR EXISTS(SELECT 1 FROM identity.panel_invitation_revocations WHERE invitation_id=inv.id)
 OR NOT EXISTS(SELECT 1 FROM identity.principals WHERE id=NEW.principal_id AND active AND issuer=inv.expected_issuer AND subject=inv.expected_subject)
 OR NOT EXISTS(SELECT 1 FROM identity.memberships WHERE id=NEW.membership_id AND study_id=NEW.study_id AND principal_id=NEW.principal_id AND active)
 OR NOT EXISTS(SELECT 1 FROM identity.panelist_links WHERE study_id=NEW.study_id AND membership_id=NEW.membership_id AND panelist_id=NEW.panelist_id)
 THEN RAISE EXCEPTION 'invitation acceptance invalid'; END IF;
 RETURN NEW; END $$;
CREATE TRIGGER validate_invitation_acceptance BEFORE INSERT ON identity.panel_invitation_acceptances FOR EACH ROW EXECUTE FUNCTION ops.guard_invitation_acceptance();
CREATE TRIGGER immutable_panel_invitation BEFORE UPDATE OR DELETE ON identity.panel_invitations FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_invitation_revocation BEFORE UPDATE OR DELETE ON identity.panel_invitation_revocations FOR EACH ROW EXECUTE FUNCTION ops.immutable();
CREATE TRIGGER immutable_invitation_acceptance BEFORE UPDATE OR DELETE ON identity.panel_invitation_acceptances FOR EACH ROW EXECUTE FUNCTION ops.immutable();
